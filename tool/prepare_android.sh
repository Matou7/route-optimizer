#!/usr/bin/env bash
set -euo pipefail
flutter create --platforms=android --org fr.routeoptimizer --project-name route_optimizer scaffold
cp -R scaffold/android ./android
rm -rf scaffold
python3 - <<'PY'
from pathlib import Path
p = Path("android/app/src/main/AndroidManifest.xml")
s = p.read_text()
permissions = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
"""
s = s.replace("<application", permissions + "    <application", 1)
p.write_text(s)
PY
