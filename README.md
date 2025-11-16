# Video Cutter - Flutter Android App

A mobile-first video cutting application for Android 11+, porting the original Python Flask web app to native Flutter. Cut, trim, and merge video segments with ease.

**Status:** Production-ready for Android 11+ devices

## 🎯 Features

- ✅ **Multi-file processing**: Upload and process multiple videos simultaneously
- ✅ **Flexible timestamps**: Support multiple time format inputs (HH:MM:SS.mmm, MM:SS, seconds, etc.)
- ✅ **Live preview**: Watch videos and edit cut ranges in real-time
- ✅ **Fast processing**: Uses FFmpeg with codec copy for zero quality loss
- ✅ **Custom output folders**: Organize results by custom folder names
- ✅ **Range merging**: Automatically merge overlapping segments
- ✅ **ZIP support**: Optional ZIP compression of all outputs
- ✅ **Progress tracking**: Real-time progress updates during processing
- ✅ **Material Design 3**: Modern, intuitive UI

## 📱 Requirements

- **Device**: Android 11+ (minSdkVersion 31)
- **RAM**: 2GB minimum (4GB+ recommended for large files)
- **Storage**: Free space equal to output size
- **Flutter**: 3.0.0+ (for development)

## 🚀 Quick Start

### Build APK (Fastest Way)

```bash
cd /workspaces/video-cutter-flutter
flutter clean && flutter pub get
flutter build apk --release --target-platform android-arm64
```

**Output:** `build/app/outputs/flutter-apk/app-release.apk`

### Install on Device

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Or transfer the APK file to your phone and tap to install.

### Full Build Guide

See [QUICK_START.md](QUICK_START.md) for detailed instructions.

## 📋 Supported Formats

**Input:** MP4, MOV, MKV, AVI, WebM  
**Output:** Same as input (no re-encoding)

## 🎬 Usage

1. **Launch app** and tap the cloud icon or upload area
2. **Select videos** from your device storage
3. **Enter timestamp ranges** (one per line):
   ```
   00:00:05.000 - 00:00:20.500
   00:25:10 to 00:30:45
   5 - 20
   ```
4. **(Optional) Customize:**
   - Output folder name
   - Merge gap threshold
   - Overwrite existing files
   - ZIP compression

5. **Tap "Start Processing"**
6. **Preview** ranges and edit if needed
7. **Process** and monitor progress
8. **Open output folder** to access cut videos

## 📂 Output Structure

```
/storage/emulated/0/Documents/VideoCutter/
├── [custom_folder_or_default]/
│   └── [YYYYMMDD]/
│       └── run-1/
│           ├── 1_1.mp4
│           ├── 1_2.mp4
│           └── ...
```

## ⏱️ Timestamp Formats

The app intelligently parses multiple timestamp formats:

| Format | Examples | Notes |
|--------|----------|-------|
| HH:MM:SS.mmm | 00:05:30.500 | Full format |
| MM:SS | 05:30 | Minutes & seconds |
| SS | 330 | Seconds only |
| Separators | `-`, `to`, `,`, space | Flexible range delimiters |

**Examples:**
```
00:00:05.000 - 00:00:20.500    ✓
5 to 20                        ✓
00:05-00:20                    ✓
5, 20                          ✓
00:00:05 00:00:20             ✓
```

## 🔧 Project Structure

```
lib/
├── main.dart                 # App entry point & theme
├── models/
│   └── video_range.dart     # Timestamp parsing & validation
├── screens/
│   ├── home_screen.dart      # File selection & input
│   ├── preview_screen.dart   # Video preview & editing
│   └── processing_screen.dart # FFmpeg processing & progress
└── utils/
    └── video_utils.dart      # ZIP creation, formatting

android/
├── app/build.gradle          # Dependencies (FFmpeg Kit)
└── src/main/
    ├── AndroidManifest.xml   # Permissions
    └── kotlin/MainActivity.kt # Flutter entry point
```

## 📦 Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `file_picker` | 6.0.0 | File selection |
| `video_player` | 2.7.2 | Video preview |
| `ffmpeg_kit_flutter_min_gpl` | 5.1.0 | Video processing |
| `path_provider` | 2.1.0 | Storage access |
| `permission_handler` | 11.4.3 | Runtime permissions |
| `archive` | 3.4.0 | ZIP creation |
| `intl` | 0.19.0 | Internationalization |
| `uuid` | 4.0.0 | Session IDs |

## 🛠️ Development

### Prerequisites

```bash
flutter --version    # >= 3.0.0
android/build.gradle  # Android Gradle Plugin 7.4.2
# Android SDK API 34
```

### Setup

```bash
flutter pub get
flutter packages get
```

### Run Debug Build

```bash
flutter run -v
```

### Run Release Build

```bash
flutter run --release
```

## 📊 Performance

- **Codec**: H.264/AAC (no re-encoding with `-c copy`)
- **Speed**: Processing speed depends on device and file size
  - Typical: 5-10x realtime on modern phones
  - Example: 60s segment processes in 6-12s
- **APK Size**: ~150-200 MB (includes FFmpeg binaries)

## 🔐 Permissions

Required permissions (requested at runtime):

- `READ_EXTERNAL_STORAGE` - Access video files
- `WRITE_EXTERNAL_STORAGE` - Save processed videos
- `ACCESS_MEDIA_LOCATION` - Read media metadata

**Android 11+ Note**: Uses scoped storage; full device access not needed.

## 📱 Device Compatibility

| Android Version | Codename | Status |
|-----------------|----------|--------|
| 14 | UpsideDownCake | ✅ Full support |
| 13 | Tiramisu | ✅ Full support |
| 12 | S | ✅ Full support |
| 11 | R | ✅ Full support (minSdkVersion) |
| 10 | Q | ⚠️ Can be supported (requires rebuild) |

## 🐛 Troubleshooting

### App crashes on startup
```bash
flutter clean && flutter pub get
flutter run --release -v
```

### FFmpeg errors during processing
- Ensure device has 2GB+ free storage
- Try with a smaller test video first
- Check that input file is a valid video format

### Permissions denied
- Grant app permissions in Settings → Apps → Video Cutter → Permissions
- For Android 11+, grant "Files and media" access

### Build APK fails
```bash
export ANDROID_HOME=$HOME/Android/Sdk
flutter build apk --release --verbose
```

### Large APK size
Use `--split-per-abi` to reduce per-architecture size:
```bash
flutter build apk --split-per-abi --release
```

## 📝 Configuration

### Change minimum Android version

Edit `android/app/build.gradle`:
```gradle
minSdkVersion 30  // Change from 31
```

### Custom FFmpeg build options

The app uses `ffmpeg_kit_flutter_min_gpl` (minimal variant). For full FFmpeg:
```yaml
ffmpeg_kit_flutter: ^5.1.0  # Full version (larger APK)
```

### Modify output codec

In `lib/screens/processing_screen.dart`, change `_cutVideo()`:
```dart
// Replace '-c copy' with re-encoding options:
'-c:v libx264 -crf 23 -c:a aac -b:a 128k'
```

## 🧪 Testing

### Test locally
```bash
flutter run --debug
```

### Test with release build
```bash
flutter run --release
```

### Test on emulator
```bash
flutter emulators --launch Pixel_5_API_34
flutter run --release
```

## 📄 License

MIT License - Based on the original Python Flask Video Cutter

## 🤝 Contributing

Contributions welcome! Please:
1. Test on Android 11+ device
2. Follow Dart style guide (`dart format .`)
3. Update tests if modifying core logic
4. Document changes in code comments

## 📞 Support

- **Flutter issues**: https://flutter.dev/docs
- **FFmpeg Kit**: https://github.com/tanersonmez/ffmpeg-kit
- **Android issues**: https://developer.android.com/

---

**Made with ❤️ for mobile video editing**