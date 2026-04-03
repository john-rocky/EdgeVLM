# iOS-VLM-Sampler

A sample iOS/macOS app showcasing various on-device Vision-Language Model (VLM) use cases powered by [EdgeVLM (FastVLM)](https://www.arxiv.org/abs/2412.13303). All inference runs privately on-device using Apple Silicon.

## Features

| Feature | Description | Platform |
|:--------|:------------|:---------|
| **Camera** | Live camera feed with real-time image captioning | iOS / macOS |
| **Chat** | Multi-turn conversation with images | iOS / macOS |
| **Detect** | Object detection with bounding box overlay | iOS / macOS |
| **Segment** | Smart segmentation — identify and mask objects in a scene | iOS / macOS |
| **Translate** | Real-time translation of captured text | iOS / macOS |
| **Narrate** | Audio narration of what the camera sees | iOS / macOS |
| **Video** | Video captioning with timeline and frame-level search | iOS / macOS |
| **Screen** | Screenshot analysis | iOS / macOS |
| **Compare** | Side-by-side image comparison | iOS / macOS |
| **Extract** | Structured data extraction from images | iOS / macOS |
| **AR Annotate** | Tap objects in AR to place floating labels in 3D space | iOS only |

## Requirements

- iOS 18.2+ / macOS 15.2+
- Xcode 16+

## Getting Started

### 1. Download a pretrained model

```shell
chmod +x app/get_pretrained_mlx_model.sh
app/get_pretrained_mlx_model.sh --model 0.5b --dest app/EdgeVLM/model
```

Available sizes:

| Model | Notes |
|:------|:------|
| **0.5B** | Small and fast — ideal for iPhone |
| **1.5B** | Balanced speed and accuracy |
| **7B** | Best accuracy — suited for iPad / Mac |

### 2. Build and run

Open `app/EdgeVLM.xcodeproj` in Xcode, then build and run on a device.

### Custom models

You can quantize or fine-tune EdgeVLM to fit your needs. See [`model_export`](../model_export/) for details. Clear `app/EdgeVLM/model` before downloading or copying a new model.

## Architecture

The app is built with SwiftUI and uses [MLX Swift](https://github.com/ml-explore/mlx-swift) for on-device LLM inference and CoreML for the vision encoder.

```
EdgeVLM App/
├── HomeView.swift              # Main navigation grid
├── EdgeVLMModel.swift          # Shared model wrapper
├── ContentView.swift           # Live camera captioning
├── Conversation/               # Multi-turn chat
├── Detection/                  # Object detection + bounding boxes
├── SmartSegment/               # VLM-driven segmentation
├── Translation/                # Real-time translation
├── Narration/                  # Audio narration
├── VideoCaptioning/            # Video caption + timeline
├── VideoSeek/                  # Frame-level search in video
├── ScreenAnalysis/             # Screenshot analysis
├── ImageCompare/               # Image comparison
├── DataExtract/                # Structured data extraction
├── ARAnnotation/               # AR annotation (iOS)
├── YOLOWorld/                  # Grounding / text-based detection
└── Shortcuts/                  # Siri Shortcuts integration
```

## License

See [LICENSE](../LICENSE) and [LICENSE_MODEL](../LICENSE_MODEL).
