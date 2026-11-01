#!/usr/bin/env bash
# Genera le cartelle di piattaforma (non salvate nel repository) e le adatta.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --project-name d_voce --org dev.dvoce --platforms=android,ios .
rm -f test/widget_test.dart

# --- Android -------------------------------------------------------------
GRADLE=android/app/build.gradle.kts
[ -f "$GRADLE" ] || GRADLE=android/app/build.gradle
# minSdk 24 (Android 7): richiesto dalle librerie audio e vocali.
sed -i -E 's/minSdk *= *flutter\.minSdkVersion/minSdk = 24/; s/minSdkVersion +flutter\.minSdkVersion/minSdkVersion 24/' "$GRADLE"
grep -n "minSdk" "$GRADLE" || true

MANIFEST=android/app/src/main/AndroidManifest.xml
# Nome visibile sotto l'icona.
sed -i 's/android:label="d_voce"/android:label="D. Voce"/' "$MANIFEST"
# Internet serve solo per scaricare le voci.
if ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$MANIFEST"
fi
grep -n "uses-permission\|android:label" "$MANIFEST" || true

# --- iOS (solo su macOS) ---------------------------------------------------
if [[ "$(uname)" == "Darwin" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName D. Voce" ios/Runner/Info.plist || true
  if [ -f ios/Podfile ]; then
    sed -i '' "s/^# platform :ios.*/platform :ios, '13.0'/" ios/Podfile || true
  fi
fi

flutter pub get
dart run flutter_launcher_icons
