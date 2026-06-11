# YeType

**On-device AI autocomplete for macOS.** YeType shows inline "ghost text" suggestions as you type in any text field, powered by a local GGUF model running entirely on your Mac — no cloud, no account, no data leaves your device.

It reads the **whole screen** around your cursor (via on-device OCR) for richer context, so suggestions fit what you're actually working on.

## Features
- ⚡ Inline ghost-text completion in native macOS text fields
- 🖥️ Full-display visual context via Apple Vision OCR (optional, local)
- 🔒 100% on-device — runs local GGUF models through `llama.cpp`
- 🎯 Tunable suggestion length, languages, and writing style

## Requirements
- macOS 14 (Sonoma)+ · Apple Silicon (M1+) · 8 GB RAM min (16 GB+ for larger models)

## Permissions
- **Accessibility** (required) — read the focused text field
- **Input Monitoring** (required) — detect typing
- **Screen Recording** (optional) — capture on-screen context for richer suggestions

## Build from source
```bash
xcodegen generate
xcodebuild -project YeType.xcodeproj -scheme "YeType" -configuration Debug build
```

## License

Built on [llama.cpp](https://github.com/ggml-org/llama.cpp) for on-device inference.
Licensed under **AGPL-3.0** (see [LICENSE](LICENSE)).
