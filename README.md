# receptionOS Visualizer

Apple Vision Pro workspace for local visualization, inspection and measurement of aligned 3D dental scan data.

`visionOS` · `SwiftUI` · `Unity 6` · `C#` · `URP` · `Metal` · `IL2CPP` · `arm64`

**Current documented release:** `2.1.5 / Build 155`  
**Target device:** Apple Vision Pro  
**Status:** tested and accepted on physical hardware

## Demo

### 1. Aligned Face, jaw and CBCT composition

[![Aligned Face, jaw and CBCT composition](media/demo-01-preview.jpg)](media/demo-01-aligned-face-jaw-cbct.mp4)

**[Open video](media/demo-01-aligned-face-jaw-cbct.mp4)** · 9 seconds · MP4

### 2. Spatial inspection and model interaction

[![Spatial inspection and model interaction](media/demo-02-preview.jpg)](media/demo-02-spatial-inspection.mp4)

**[Open video](media/demo-02-spatial-inspection.mp4)** · 24 seconds · MP4

## Abstract

receptionOS Visualizer is a hybrid native visionOS and Unity application for working with multi-model 3D scan cases in physical space.

The system imports scanner-derived geometry locally, preserves model roles and alignment, renders Face, oral and CBCT data using separate visual profiles, and supports measurement between surfaces belonging to different models in the same aligned composition.

The main engineering problem was not displaying a mesh. It was preserving consistent meaning across file parsing, model roles, transforms, source scale, rendering, native visionOS lifecycle and the Unity runtime.

## System architecture

The application is hybrid by design:

- **Swift 6 and SwiftUI** own native windows, Files integration, localization, privacy-facing UI and visionOS lifecycle.
- **Objective-C++ and JSON** provide an explicit protocol between the native application and Unity.
- **Unity 6000.3.19f1 and C#** own scan import, mesh state, model transforms, spatial tools and rendering logic.
- **URP and Metal** provide the real-time rendering path on Apple Vision Pro.
- **IL2CPP** converts managed Unity assemblies to C++ for ahead-of-time arm64 deployment through Apple's toolchain.

The native and Unity layers do not exchange unstructured callbacks. Commands carry request identity and are completed through terminal acknowledgement, postcondition checks and a published state snapshot. This prevents stale lifecycle effects from silently mutating the scene.

## Data pipeline

The importer supports the scanner data encountered during development:

- ASCII and binary little-endian PLY;
- vertex positions, triangles, normals, colors and texture coordinates;
- vertex-color and external PNG/JPEG appearance data;
- optional alignment sidecars such as `.matrix4`;
- semantic roles including Face, upper jaw, lower jaw and CBCT;
- explicit validation before expensive mesh allocation.

The accepted guardrails included:

- 512 MB maximum input file size;
- 1.5 million vertices per imported model;
- 3 million triangles per imported model;
- 10 models in one workspace.

## Rendering

Different scan roles require different rendering assumptions.

### Face

Face rendering preserves source texture information while applying bounded color statistics and GPU-side naturalization. An earlier full-atlas CPU path was rejected after it triggered the physical-device watchdog. The accepted path keeps CPU work bounded and moves per-pixel correction to the GPU.

### Oral scans

Oral models use their scanner-provided color information together with controlled cavity, depth, ambient-occlusion and material response. The accepted V7 / Build 148 zero-settings appearance is treated as an immutable baseline.

### CBCT

CBCT models use a separate rendering profile so that later calibration work cannot silently change the accepted bone/CBCT baseline.

Controls that could not be made reliable without scanner-independent anatomical segmentation were deliberately disabled instead of exposing misleading behavior.

## Spatial measurement

The ruler operates on mesh surfaces, not model origins or bounding boxes.

- A BVH accelerates closest-surface queries.
- The final point is calculated on the actual candidate triangle.
- Each ruler endpoint stores the model surface to which it is attached.
- A standalone model is measured in its source coordinate system.
- An aligned composition uses one shared measurement context across all eligible visible models.
- One endpoint can therefore attach to a tooth while the other attaches to a separate Face surface.

Changing the active model inside the same composition does not change the physical meaning of the measurement. Leaving the composition resets the ruler context.

## Native lifecycle and state

Physical Apple Vision Pro testing exposed lifecycle races that were not sufficiently visible in the simulator. The final design uses reducer-style state with run and effect identifiers for window and spatial-runtime operations.

This provides:

- deterministic startup and reconnection;
- rejection of stale asynchronous completions;
- separation between active model and multi-selection;
- explicit closed, connecting, preparing, ready and failure states;
- consistent state after opening or closing native windows.

## Engineering questions addressed

1. How can separately imported meshes preserve a shared spatial and metric context?
2. How should CPU and GPU work be divided for high-resolution Face appearance correction on a wearable device?
3. How can native visionOS lifecycle and embedded Unity state converge deterministically?
4. How can a rendering baseline remain stable while role-specific calibration is added?
5. How should an importer fail before untrusted geometry produces excessive memory or processing cost?

## Validation snapshot

Build 155 was validated using:

- **36,115 authored lines** across Swift, Objective-C++, C#, shaders and tests;
- **101 EditMode tests**;
- **33 PlayMode tests**;
- Swift 6 / XROS strict compilation;
- clean fail-closed Unity-to-Xcode export;
- unsigned and signed builds;
- codesign, plist, target-membership, multi-scene and privacy checks;
- acceptance of the exact build on physical Apple Vision Pro hardware.

The automated tests included importer variants, role resolution, rendering baseline regression, atomic Face presets, multi-selection, deterministic localization, lifecycle state and cross-model measurement behavior.

## Selected device-level lessons

- **Build 149:** full Face atlas work on the CPU caused an AVP watchdog failure. The correction path was redesigned around bounded CPU statistics and GPU processing.
- **Build 151:** a singleton window/openWindow race caused inconsistent lifecycle behavior. The fix was a reducer with explicit run/effect identity.
- **Build 148 onward:** the accepted V7 rendering result became a regression baseline rather than a value that later features were allowed to reinterpret.

## My contribution

I worked across the complete system:

- product and runtime architecture;
- native SwiftUI and visionOS integration;
- Unity runtime and model-state design;
- PLY import and defensive validation;
- role-aware URP/Metal rendering;
- Face performance stabilization;
- multi-model composition and measurement;
- native-to-Unity protocol design;
- automated tests, export validation and physical-device release stabilization.

## Scope

This repository is a technical portfolio, not the application source repository.

It intentionally contains no Unity project, exported Xcode application, patient data, raw scans, private fixtures, signing material or client-confidential release assets.

The project is described as a local-first spatial visualization system. No medical-device certification or clinical-outcome claim is made.

## References

- [Apple visionOS](https://developer.apple.com/visionos/)
- [Unity development for visionOS](https://docs.unity3d.com/current/Manual/visionOS.html)
- [Unity IL2CPP](https://docs.unity3d.com/current/Manual/scripting-backends-il2cpp.html)

## Contact

**Jakub Majewski**  
XR and Spatial Computing  
[github.com/jacobemanuel](https://github.com/jacobemanuel)
