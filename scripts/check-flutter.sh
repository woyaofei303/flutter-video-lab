#!/usr/bin/env sh
set -eu
export CI=true
export FLUTTER_SUPPRESS_ANALYTICS=true
sh scripts/flutterw dart format --output=none --set-exit-if-changed lib test integration_test
sh scripts/flutterw analyze --no-pub
sh scripts/flutterw test --no-pub
