# Multispeaker Fastpitch HifiVGan Engine

A Swift library for on-device text-to-speech synthesis using FastPitch and HiFiGAN models. Generate natural-sounding speech directly on iOS devices without any network connection or external API dependencies.

## Features

- 🎯 **100% On-Device Processing** - All speech synthesis happens locally on your device
- 🚀 **Fast Generation** - Optimized CoreML models for quick audio generation
- 🔒 **Privacy-First** - No data leaves your device
- 📱 **iOS Native** - Built specifically for Apple platforms
- 🎵 **High Quality** - 22.05kHz sample rate with natural prosody

## Requirements

- iOS 15.0+ / macOS 12.0+
- Swift 5.7+
- Xcode 14.0+

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/philipdaquin/OtosakuTTS-iOS.git", from: "1.0.0")
]
```

Or in Xcode:
1. Go to File → Add Package Dependencies
2. Enter: `https://github.com/Otosaku/OtosakuTTS-iOS.git`
3. Select version 1.0.0 or later

## Model Setup

### Download Models

Download the required model archive from:
```
https://firebasestorage.googleapis.com/v0/b/ocre-82770.firebasestorage.app/o/TTSModels.zip?alt=media&token=f9d7c1ca-b38d-48c7-84e3-34be0c5a65a5
```

The archive contains:
- `FastPitch.mlmodelc` - Text-to-spectrogram model
- `HiFiGan.mlmodelc` - Spectrogram-to-audio vocoder
- `tokens.txt` - Phoneme token mappings
- `cmudict.json` - CMU pronunciation dictionary

### Extract Models

Extract the archive and ensure your directory structure looks like:
```
YourModelsDirectory/
├── FastPitch.mlmodelc/
├── HiFiGan.mlmodelc/
├── tokens.txt
└── cmudict.json
```

## Usage

### Basic Example

```swift
import OtosakuTTS_iOS
import AVFoundation

// Initialize TTS with path to models directory
let modelsURL = URL(fileURLWithPath: "/path/to/models")
let tts = try OtosakuTTS(modelDirectoryURL: modelsURL)

// Generate speech
let audioBuffer = try tts.generate(text: "Hello, world!")

// Play the audio
let audioEngine = AVAudioEngine()
let playerNode = AVAudioPlayerNode()

audioEngine.attach(playerNode)
audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: audioBuffer.format)
try audioEngine.start()

playerNode.scheduleBuffer(audioBuffer)
playerNode.play()
```

### Advanced Configuration

```swift
// Use specific compute units for performance tuning
let tts = try OtosakuTTS(
    modelDirectoryURL: modelsURL,
    computeUnits: .cpuAndGPU  // or .cpuOnly, .all
)
```

### Error Handling

```swift
do {
    let tts = try OtosakuTTS(modelDirectoryURL: modelsURL)
    let buffer = try tts.generate(text: inputText)
    // Use the buffer
} catch OtosakuTTSError.modelLoadingFailed(let model) {
    print("Failed to load \(model)")
} catch OtosakuTTSError.emptyInput {
    print("Please provide text to synthesize")
} catch {
    print("TTS Error: \(error)")
}
```

## Example App

Check out the [Example](Example/) directory for a complete iOS app demonstrating:
- Automatic model downloading and extraction
- Text input interface
- Audio playback
- Progress indicators
- Error handling

To run the example:
1. Open `Example/Example.xcodeproj`
2. Build and run
3. The app will automatically download models on first launch

## Architecture

The library uses a two-stage synthesis pipeline:

1. **FastPitch** - Converts text/phonemes to mel-spectrograms with pitch information
2. **HiFiGAN** - Converts spectrograms to high-quality audio waveforms

Both models run entirely on-device using CoreML for optimal performance.

## Current Limitations & Contributing

### Tokenizer Improvements Needed

The current tokenizer is quite basic and there's significant room for improvement in synthesis quality through better text processing. Current limitations include:

- Simple phoneme mapping without context awareness
- Limited handling of abbreviations and numbers
- Basic punctuation processing
- No support for emphasis or emotion markers

**We welcome contributors!** If you're interested in improving the tokenizer to enhance speech quality, please feel free to submit PRs or open issues with suggestions.

Areas for contribution:
- Better text normalization (numbers, dates, abbreviations)
- Context-aware phoneme selection
- Prosody prediction
- Multi-language support
- Custom pronunciation dictionaries

## Performance

Typical generation times on modern iOS devices:
- iPhone 14 Pro: ~0.5s for a typical sentence
- iPhone 12: ~0.8s for a typical sentence
- iPad Pro M2: ~0.3s for a typical sentence

Memory usage: ~200MB when models are loaded

## Mac Release

The Mac release path matches StorageScanner: build a signed app locally, then notarize and publish it to GitHub. Sparkle uses the same appcast.

Fill in `release.env` from `release.env.example`. That file is gitignored. Put your Developer ID, notarization, and Sparkle values there. Do not commit it.

```bash
cp release.env.example release.env
```

`version.env` holds `MARKETING_VERSION` and `BUILD_NUMBER`. The example app's marketing version should stay in step with it.

Before publishing, check that the tools and secrets are present. This prints names only, not secret values.

```bash
scripts/release-doctor.sh
scripts/release-doctor.sh --github
```

Build locally without creating a GitHub Release:

```bash
scripts/release.sh local
```

`local` builds the Example scheme for macOS, signs `Example.app`, writes the DMG and Sparkle ZIP, and generates `appcast.xml` under `.release/`.

Publish a new GitHub Release, notarize the DMG, upload the DMG and ZIP, and refresh the appcast:

```bash
scripts/release.sh publish
```

`upload` does the same build, sign, and notarize work, then uploads those assets to an existing GitHub Release for the current version tag.

Release notes are drafted from commit subjects with `scripts/release-notes.sh`. The draft is written into the release workspace so you can edit it before publishing. `gh release create` uses that file as the GitHub Release body.

`CHANGELOG.md` is the user-facing history. The Sparkle appcast points at the downloadable update and links back to the GitHub Release notes.

### GitHub Actions

The workflow is `.github/workflows/release.yml`.

It runs when a GitHub Release is published, and it can also be started by hand with `publish` or `upload`. A published release uses `upload`, so the workflow attaches the built assets to the release you just created.

GitHub secrets:

- `DEVELOPER_ID_IDENTITY`
- `DEVELOPER_ID_CERTIFICATE_P12_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `NOTARYTOOL_PROFILE` or `NOTARYTOOL_API_KEY_P8`, `NOTARYTOOL_API_KEY_ID`, `NOTARYTOOL_API_ISSUER_ID`
- `SPARKLE_PRIVATE_KEY` or the legacy `SPARKLE_PRIVATE_KEY_FILE` secret containing the private key text
- `SPARKLE_PUBLIC_ED_KEY`

Export the Developer ID Application certificate from Keychain Access as a password-protected `.p12`, then store it:

```bash
base64 -i /path/to/DeveloperIDApplication.p12 | pbcopy
gh secret set DEVELOPER_ID_CERTIFICATE_P12_BASE64 --repo philipdaquin/OtosakuTTS-iOS
gh secret set DEVELOPER_ID_CERTIFICATE_PASSWORD --repo philipdaquin/OtosakuTTS-iOS
```

Paste the base64 output for `DEVELOPER_ID_CERTIFICATE_P12_BASE64`, and paste the `.p12` export password for `DEVELOPER_ID_CERTIFICATE_PASSWORD`.

After a successful publish or upload, the workflow uploads the DMG and ZIP, then commits the updated `appcast.xml` back to the default branch.

The shipped app is the Example target, built with `-sdk macosx`. Sparkle is linked only for macOS. Update checks stay off until `release.env` supplies `APPCAST_URL` and `SPARKLE_PUBLIC_ED_KEY`; the release build writes those into the app.

## License

This project is available under the MIT license. See the LICENSE file for more info.

## Acknowledgments

- FastPitch and HiFiGAN model architectures by NVIDIA
- CMU Pronouncing Dictionary for phoneme mappings

## Support

For issues, questions, or suggestions, please open an issue on [GitHub](https://github.com/Otosaku/OtosakuTTS-iOS/issues).

---

Made with ❤️ for the iOS community
