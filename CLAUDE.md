# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EdgeVLM is a vision-language model implementation focused on efficient vision encoding. The project includes:
- PyTorch model implementation based on LLaVA architecture
- Model export tools for Apple Silicon deployment
- iOS/macOS app for on-device inference
- Support for multiple model sizes (0.5B, 1.5B, 7B parameters)

## Architecture

### Core Components

**Model Architecture (`llava/`)**
- Vision encoder: FastViTHD - a hybrid vision encoder that outputs fewer tokens for efficient high-resolution image processing
- Language models: Supports Qwen2, LLaMA, Mistral, and MPT backends
- Multimodal fusion: Projects vision features to language model embedding space
- Training stages: Stage 2 (pretraining) and Stage 3 (fine-tuning)

**Key Directories**
- `llava/model/`: Core model implementations including vision encoders, language models, and multimodal projectors
- `llava/model/multimodal_encoder/`: Vision encoder implementations (CLIP, MobileCLIP)
- `llava/model/language_model/`: LLM backend integrations
- `model_export/`: Tools for exporting models to CoreML and MLX formats
- `app/`: iOS/macOS application code (Swift/Xcode project)

## Common Commands

### Setup and Installation
```bash
# Create conda environment
conda create -n edgevlm python=3.10
conda activate edgevlm
pip install -e .
```

### Download Pretrained Models
```bash
# Download all PyTorch checkpoints
bash get_models.sh

# Download specific model for iOS app
chmod +x app/get_pretrained_mlx_model.sh
app/get_pretrained_mlx_model.sh --model 0.5b --dest app/EdgeVLM/model
```

### Inference
```bash
# Run PyTorch inference
python predict.py --model-path /path/to/checkpoint \
                  --image-file /path/to/image.png \
                  --prompt "Describe the image."
```

### Model Export for Apple Silicon
```bash
# Export vision encoder to CoreML
python model_export/export_vision_encoder.py --model-path /path/to/checkpoint

# Install mlx-vlm with EdgeVLM patch
git clone https://github.com/Blaizzy/mlx-vlm.git
cd mlx-vlm
git checkout 1884b551bc741f26b2d54d68fa89d4e934b9a3de
git apply ../fastvlm_mlx-vlm.patch
pip install -e .

# Export to MLX format
python -m mlx_vlm.convert --hf-path /path/to/checkpoint \
                          --mlx-path /path/to/exported \
                          --only-llm \
                          -q --q-bits 8  # Optional quantization
```

### Build iOS/macOS App
1. Download model: `app/get_pretrained_mlx_model.sh --model 0.5b --dest app/EdgeVLM/model`
2. Open `app/EdgeVLM.xcodeproj` in Xcode
3. Build and run (requires iOS 18.2+ or macOS 15.2+)

## Model Configuration

The project uses Qwen2 as the default conversation mode (`conv_mode: "qwen_2"`). Model configs include:
- Vision encoder settings in model checkpoint's `config.json`
- Tokenizer configuration in `tokenizer_config.json`
- Generation parameters can be customized via command-line arguments

## Key Implementation Details

- Default device for inference: MPS (Apple Silicon)
- Image processing: Converts to RGB, applies model-specific preprocessing
- Token handling: Uses special image tokens (`<image>`) in prompts
- Supports multi-stage training with different model checkpoints per stage