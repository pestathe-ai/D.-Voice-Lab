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

# Manifest: nome dell'app, permessi e servizio per leggere a schermo spento
# (notifica con i comandi, schermata di blocco, cuffie).
python3 - <<'PY'
import re
p = 'android/app/src/main/AndroidManifest.xml'
s = open(p).read()
s = s.replace('android:label="d_voce"', 'android:label="D. Voce"')
if 'xmlns:tools' not in s:
    s = s.replace('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)
perms = [
    'android.permission.INTERNET',
    'android.permission.WAKE_LOCK',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
    'android.permission.POST_NOTIFICATIONS',
]
add = ''.join(f'    <uses-permission android:name="{x}"/>\n' for x in perms if x not in s)
s = s.replace('<application', add + '    <application', 1)
# Link "Torna a D. Voce" (dvoce://…) dalla pagina aperta in Edge. Il
# deep linking automatico di Flutter va spento: i link li gestisce l'app.
if 'android:scheme="dvoce"' not in s:
    s = s.replace('</activity>', '''    <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="dvoce" />
            </intent-filter>
            <meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
        </activity>''', 1)
service = '''
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
'''
# Android 11+: per vedere i motori di sintesi vocale installati (Google, Samsung…).
if 'android.intent.action.TTS_SERVICE' not in s:
    s = s.replace('<application', '''<queries>
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE" />
        </intent>
    </queries>
    <application''', 1)
if 'com.ryanheise.audioservice.AudioService"' not in s:
    s = s.replace('</application>', service + '    </application>', 1)
open(p, 'w').write(s)
PY
grep -n "uses-permission\|android:label\|AudioService\|tools" android/app/src/main/AndroidManifest.xml || true

# MainActivity: servizio audio a schermo spento + ponte con Microsoft Edge.
MA=$(find android/app/src/main -name 'MainActivity.kt' | head -1)
PKG=$(grep -m1 '^package ' "$MA" | awk '{print $2}')
sed "s/__PACKAGE__/$PKG/" tool/android/MainActivity.kt > "$MA"
echo "MainActivity: $MA ($PKG)"

# --- iOS (solo su macOS) ---------------------------------------------------
if [[ "$(uname)" == "Darwin" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName D. Voce" ios/Runner/Info.plist || true
  /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes array" ios/Runner/Info.plist || true
  /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes:0 string audio" ios/Runner/Info.plist || true
  if [ -f ios/Podfile ]; then
    sed -i '' "s/^# platform :ios.*/platform :ios, '15.0'/" ios/Podfile || true
  fi
fi

flutter pub get
dart run flutter_launcher_icons
