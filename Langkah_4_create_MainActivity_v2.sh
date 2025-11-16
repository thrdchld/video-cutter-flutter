# Langkah_4_create_MainActivity_v2.sh
set -e

# 1) Try to get applicationId from android/app/build.gradle
APP_ID=$(grep -Po 'applicationId\s*"\K[^"]+' android/app/build.gradle 2>/dev/null || true)

# 2) If not found, try AndroidManifest.xml package attribute
if [ -z "$APP_ID" ]; then
  APP_ID=$(grep -Po 'package="\K[^"]+' android/app/src/main/AndroidManifest.xml 2>/dev/null || true)
fi

if [ -z "$APP_ID" ]; then
  echo "ERROR: applicationId / package not found in build.gradle or AndroidManifest.xml."
  echo "Please open android/app/build.gradle and check 'applicationId' value, then run this step again."
  exit 1
fi

echo "Detected applicationId: $APP_ID"

# 3) Prepare package path (kotlin style)
PKG_PATH=${APP_ID//./\/}
DEST_DIR="android/app/src/main/kotlin/$PKG_PATH"
mkdir -p "$DEST_DIR"

MAIN_KT="$DEST_DIR/MainActivity.kt"

# 4) Write MainActivity.kt (v2 embedding)
cat > "$MAIN_KT" <<KOTLIN
package $APP_ID

import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
}
KOTLIN

echo "Wrote MainActivity.kt to: $MAIN_KT"

# 5) Show current MainActivity locations (for verification)
echo
echo "Existing MainActivity files in android/app/src/main:"
find android/app/src/main -maxdepth 4 -type f -name "MainActivity.*" -print || true

echo
echo "If you previously had an old MainActivity under java/ or kotlin/ with v1 embedding,"
echo "you can keep or remove it; Flutter will use the new Kotlin file above for v2 embedding."
echo "Now run: flutter clean && flutter pub get && flutter build apk --release"
