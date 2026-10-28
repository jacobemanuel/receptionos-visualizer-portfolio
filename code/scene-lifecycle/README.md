# Scene lifecycle for one Unity runtime and several windows

[![scene-lifecycle tests](https://github.com/jacobemanuel/receptionos-visualizer-portfolio/actions/workflows/scene-lifecycle.yml/badge.svg)](https://github.com/jacobemanuel/receptionos-visualizer-portfolio/actions/workflows/scene-lifecycle.yml)

A small piece of receptionOS Visualizer, the fix for the Build 151 lifecycle race, taken out of the app with its tests. Names are neutral and the rest of the app stays private.

## The problem

The app runs one Unity runtime behind several native visionOS windows. UIKit reports lifecycle callbacks per window, while Unity only knows one state for the whole app. Passed straight through, moving focus from one window to another looks to Unity like the app going inactive, so it pauses for a moment. When the app really goes to the background, the windows report in no fixed order, sometimes background before resign.

## What the reducer does

- It keeps the sets of connected, foreground and active windows and derives one phase for the whole app: background, foreground inactive or foreground active.
- A step up goes to Unity at once. A step down waits 100 ms. If another window becomes active in that time, it was a focus change and Unity hears nothing.
- After the wait it forwards the steps in a fixed order, resign before background, whatever order UIKit used.
- Each wait has a generation number, so a late timer from an older change can't act on a newer state.

It is a plain value type on Foundation only, so all of this is covered by unit tests without a headset.

## Files

- `Package.swift`: the package, for macOS, iOS and visionOS.
- `Sources/SceneLifecycle/SceneLifecycleReducer.swift`: the reducer.
- `Tests/SceneLifecycleTests/`: seven tests, from the first window coming up to a stale timer.
- `Example/AggregatingUnitySceneDelegate.swift`: how the app plugs it in. A subclass of the `UnitySwiftUISceneDelegate` that Unity generates decides which callbacks reach Unity and when. It needs the Unity export, so it is not part of the package build.

## Run the tests

```bash
swift test
```
