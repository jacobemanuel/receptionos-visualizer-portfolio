// Reference only: how the app plugs SceneLifecycleReducer into Unity's visionOS scene delegate.
// It needs UnitySwiftUISceneDelegate, which Unity generates into the Xcode export, so this file is
// not part of the package build. In the app a post-build step installs this class in place of the
// generated delegate.

import Foundation
import UIKit
import os
import SceneLifecycle

let aggregatedApplicationDidEnterBackground = Notification.Name("AggregatedApplicationDidEnterBackground")
let aggregatedApplicationWillEnterForeground = Notification.Name("AggregatedApplicationWillEnterForeground")

/// Process-wide scene aggregation. Opening, closing or moving focus between the
/// app's native windows must not pause the single Unity runtime.
@MainActor
private final class UnitySceneLifecycleCoordinator {
    static let shared = UnitySceneLifecycleCoordinator()

    private let runID = String(UUID().uuidString.prefix(8)).lowercased()
    private let logger = Logger(subsystem: "com.example.app", category: "SceneLifecycle")
    private var reducer = SceneLifecycleReducer()
    private var pendingSettleTask: Task<Void, Never>?

    func receive(
        _ event: SceneLifecycleRawEvent,
        forward: @escaping @MainActor ([SceneLifecycleForwardEvent]) -> Void
    ) {
        let effect = reducer.receive(event)
        apply(effect, source: event.diagnosticName, forward: forward)
    }

    private func apply(
        _ effect: SceneLifecycleEffect,
        source: String,
        forward: @escaping @MainActor ([SceneLifecycleForwardEvent]) -> Void
    ) {
        switch effect.settleDirective {
        case .unchanged:
            break

        case .cancel:
            pendingSettleTask?.cancel()
            pendingSettleTask = nil

        case .schedule(let generation):
            pendingSettleTask?.cancel()
            pendingSettleTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: SceneLifecycleReducer.settleNanoseconds)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                self.pendingSettleTask = nil
                let settledEffect = self.reducer.settle(generation: generation)
                self.log(settledEffect, source: "settle")
                if !settledEffect.forwardedEvents.isEmpty {
                    forward(settledEffect.forwardedEvents)
                }
            }
        }

        log(effect, source: source)
        if !effect.forwardedEvents.isEmpty {
            forward(effect.forwardedEvents)
        }
    }

    private func log(_ effect: SceneLifecycleEffect, source: String) {
        let snapshot = effect.snapshot
        let forwarded = effect.forwardedEvents.map(\.rawValue).joined(separator: ",")
        logger.info("run=\(self.runID, privacy: .public) effect=\(snapshot.effectID, privacy: .public) source=\(source, privacy: .public) phase=\(snapshot.phase.rawValue, privacy: .public) scenes=\(snapshot.connectedCount, privacy: .public)/\(snapshot.foregroundCount, privacy: .public)/\(snapshot.activeCount, privacy: .public) forward=\(forwarded, privacy: .public)")
    }
}

/// Unity keeps its own lifecycle handling in the base class. This subclass only decides
/// which callbacks reach it, and when.
@MainActor
final class AggregatingUnitySceneDelegate: UnitySwiftUISceneDelegate {
    private var sceneID: String?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        sceneID = session.persistentIdentifier
        receive(.connect(session.persistentIdentifier), for: scene)
    }

    override func sceneDidBecomeActive(_ scene: UIScene) {
        receive(.didBecomeActive(identifier(for: scene)), for: scene)
    }

    override func sceneWillResignActive(_ scene: UIScene) {
        receive(.willResignActive(identifier(for: scene)), for: scene)
    }

    override func sceneWillEnterForeground(_ scene: UIScene) {
        receive(.willEnterForeground(identifier(for: scene)), for: scene)
    }

    override func sceneDidEnterBackground(_ scene: UIScene) {
        receive(.didEnterBackground(identifier(for: scene)), for: scene)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        receive(.disconnect(identifier(for: scene)), for: scene)
        sceneID = nil
    }

    private func receive(_ event: SceneLifecycleRawEvent, for scene: UIScene) {
        UnitySceneLifecycleCoordinator.shared.receive(event) { [self, scene] forwardedEvents in
            self.forward(forwardedEvents, using: scene)
        }
    }

    private func identifier(for scene: UIScene) -> String {
        if let value = scene.session.persistentIdentifier as String?, !value.isEmpty {
            sceneID = value
            return value
        }
        if let sceneID { return sceneID }
        let fallback = "unbound-\(ObjectIdentifier(scene).hashValue)"
        sceneID = fallback
        return fallback
    }

    private func forward(_ events: [SceneLifecycleForwardEvent], using scene: UIScene) {
        for event in events {
            switch event {
            case .willEnterForeground:
                super.sceneWillEnterForeground(scene)
                NotificationCenter.default.post(name: aggregatedApplicationWillEnterForeground, object: nil)

            case .didBecomeActive:
                super.sceneDidBecomeActive(scene)

            case .willResignActive:
                super.sceneWillResignActive(scene)

            case .didEnterBackground:
                super.sceneDidEnterBackground(scene)
                NotificationCenter.default.post(name: aggregatedApplicationDidEnterBackground, object: nil)
            }
        }
    }
}
