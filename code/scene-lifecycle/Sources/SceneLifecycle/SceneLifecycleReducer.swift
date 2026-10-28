import Foundation

/// Aggregate process state delivered to Unity. The ordering is intentionally
/// stronger than UIKit's per-scene callback ordering.
public enum SceneLifecyclePhase: String, Sendable, Equatable {
    case background
    case foregroundInactive
    case foregroundActive
}

/// What the single Unity runtime gets told, in this order.
public enum SceneLifecycleForwardEvent: String, Sendable, Equatable {
    case willEnterForeground
    case didBecomeActive
    case willResignActive
    case didEnterBackground
}

/// One UIKit callback for one native window, identified by its scene session.
public enum SceneLifecycleRawEvent: Sendable, Equatable {
    case connect(String)
    case willEnterForeground(String)
    case didBecomeActive(String)
    case willResignActive(String)
    case didEnterBackground(String)
    case disconnect(String)

    /// A privacy-safe diagnostic label. Scene identifiers never enter logs.
    public var diagnosticName: String {
        switch self {
        case .connect: return "connect"
        case .willEnterForeground: return "will_enter_foreground"
        case .didBecomeActive: return "did_become_active"
        case .willResignActive: return "will_resign_active"
        case .didEnterBackground: return "did_enter_background"
        case .disconnect: return "disconnect"
        }
    }

    fileprivate var sceneID: String {
        switch self {
        case .connect(let id),
             .willEnterForeground(let id),
             .didBecomeActive(let id),
             .willResignActive(let id),
             .didEnterBackground(let id),
             .disconnect(let id):
            return id
        }
    }
}

/// What the caller does with its settle timer after an event.
public enum SceneLifecycleSettleDirective: Sendable, Equatable {
    case unchanged
    case cancel
    case schedule(UInt64)
}

public struct SceneLifecycleSnapshot: Sendable, Equatable {
    public let effectID: UInt64
    public let phase: SceneLifecyclePhase
    public let connectedCount: Int
    public let foregroundCount: Int
    public let activeCount: Int
}

public struct SceneLifecycleEffect: Sendable, Equatable {
    public let forwardedEvents: [SceneLifecycleForwardEvent]
    public let settleDirective: SceneLifecycleSettleDirective
    public let snapshot: SceneLifecycleSnapshot
}

/// Foundation-only reducer for all native scenes sharing one Unity runtime.
///
/// Downward transitions are held for a single 100 ms settle window. An active
/// scene appearing during that window makes a focus handoff a no-op. A genuine
/// background is reconciled as resign -> background even when UIKit reports the
/// raw background callback first.
public struct SceneLifecycleReducer: Sendable, Equatable {
    public static let settleNanoseconds: UInt64 = 100_000_000

    public private(set) var connectedSceneIDs: Set<String> = []
    public private(set) var foregroundSceneIDs: Set<String> = []
    public private(set) var activeSceneIDs: Set<String> = []
    public private(set) var deliveredPhase: SceneLifecyclePhase = .background
    public private(set) var pendingSettleGeneration: UInt64?

    private var nextEffectID: UInt64 = 0
    private var nextSettleGeneration: UInt64 = 0

    public init() {}

    public mutating func receive(_ event: SceneLifecycleRawEvent) -> SceneLifecycleEffect {
        advanceEffectID()

        let id = event.sceneID
        var aggregateAvailabilityChanged = false
        if !id.isEmpty {
            switch event {
            case .connect:
                connectedSceneIDs.insert(id)

            case .willEnterForeground:
                connectedSceneIDs.insert(id)
                aggregateAvailabilityChanged = foregroundSceneIDs.insert(id).inserted

            case .didBecomeActive:
                connectedSceneIDs.insert(id)
                let foregroundChanged = foregroundSceneIDs.insert(id).inserted
                let activeChanged = activeSceneIDs.insert(id).inserted
                aggregateAvailabilityChanged = foregroundChanged || activeChanged

            case .willResignActive:
                aggregateAvailabilityChanged = activeSceneIDs.remove(id) != nil

            case .didEnterBackground:
                // Background implies inactive. Removing both here makes the
                // reducer independent of per-scene callback order.
                let activeChanged = activeSceneIDs.remove(id) != nil
                let foregroundChanged = foregroundSceneIDs.remove(id) != nil
                aggregateAvailabilityChanged = activeChanged || foregroundChanged

            case .disconnect:
                connectedSceneIDs.remove(id)
                let activeChanged = activeSceneIDs.remove(id) != nil
                let foregroundChanged = foregroundSceneIDs.remove(id) != nil
                aggregateAvailabilityChanged = activeChanged || foregroundChanged
            }
        }

        let desiredPhase = aggregatePhase
        var forwardedEvents: [SceneLifecycleForwardEvent] = []
        var directive: SceneLifecycleSettleDirective = .unchanged

        if desiredPhase.rank > deliveredPhase.rank {
            if pendingSettleGeneration != nil { directive = .cancel }
            pendingSettleGeneration = nil
            forwardedEvents = transitionEvents(from: deliveredPhase, to: desiredPhase)
            deliveredPhase = desiredPhase
        } else if desiredPhase.rank < deliveredPhase.rank {
            if aggregateAvailabilityChanged {
                advanceSettleGeneration()
                pendingSettleGeneration = nextSettleGeneration
                directive = .schedule(nextSettleGeneration)
            }
        } else if pendingSettleGeneration != nil {
            // The aggregate recovered to its already-delivered phase before
            // the settle deadline (the normal native-window focus handoff).
            pendingSettleGeneration = nil
            directive = .cancel
        }

        return effect(forwardedEvents: forwardedEvents, directive: directive)
    }

    /// Called when a scheduled settle timer fires. A timer from an older generation does nothing.
    public mutating func settle(generation: UInt64) -> SceneLifecycleEffect {
        advanceEffectID()
        guard pendingSettleGeneration == generation else {
            return effect(forwardedEvents: [], directive: .unchanged)
        }

        pendingSettleGeneration = nil
        let desiredPhase = aggregatePhase
        let forwardedEvents = transitionEvents(from: deliveredPhase, to: desiredPhase)
        deliveredPhase = desiredPhase
        return effect(forwardedEvents: forwardedEvents, directive: .unchanged)
    }

    private var aggregatePhase: SceneLifecyclePhase {
        if !activeSceneIDs.isEmpty { return .foregroundActive }
        if !foregroundSceneIDs.isEmpty { return .foregroundInactive }
        return .background
    }

    private mutating func advanceEffectID() {
        nextEffectID &+= 1
        if nextEffectID == 0 { nextEffectID = 1 }
    }

    private mutating func advanceSettleGeneration() {
        nextSettleGeneration &+= 1
        if nextSettleGeneration == 0 { nextSettleGeneration = 1 }
    }

    private func effect(
        forwardedEvents: [SceneLifecycleForwardEvent],
        directive: SceneLifecycleSettleDirective
    ) -> SceneLifecycleEffect {
        SceneLifecycleEffect(
            forwardedEvents: forwardedEvents,
            settleDirective: directive,
            snapshot: SceneLifecycleSnapshot(
                effectID: nextEffectID,
                phase: deliveredPhase,
                connectedCount: connectedSceneIDs.count,
                foregroundCount: foregroundSceneIDs.count,
                activeCount: activeSceneIDs.count))
    }

    private func transitionEvents(
        from source: SceneLifecyclePhase,
        to destination: SceneLifecyclePhase
    ) -> [SceneLifecycleForwardEvent] {
        switch (source, destination) {
        case (.background, .foregroundInactive):
            return [.willEnterForeground]
        case (.background, .foregroundActive):
            return [.willEnterForeground, .didBecomeActive]
        case (.foregroundInactive, .background):
            return [.didEnterBackground]
        case (.foregroundInactive, .foregroundActive):
            return [.didBecomeActive]
        case (.foregroundActive, .background):
            return [.willResignActive, .didEnterBackground]
        case (.foregroundActive, .foregroundInactive):
            return [.willResignActive]
        default:
            return []
        }
    }
}

private extension SceneLifecyclePhase {
    var rank: Int {
        switch self {
        case .background: return 0
        case .foregroundInactive: return 1
        case .foregroundActive: return 2
        }
    }
}
