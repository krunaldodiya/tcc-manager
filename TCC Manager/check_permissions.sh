#!/bin/bash

# Check TCC permissions for an app
# Usage: check_permissions.sh <app_path>

APP_PATH="$1"

if [ -z "$APP_PATH" ]; then
  echo "{\"bundleId\":\"\",\"camera\":0,\"microphone\":0}"
  exit 0
fi

# Get bundle ID from app
BUNDLE_ID=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)

if [ -z "$BUNDLE_ID" ]; then
  echo "{\"bundleId\":\"\",\"camera\":0,\"microphone\":0}"
  exit 0
fi

# Query TCC database to check permissions
# Try user database first, then system database
TCC_DB_USER="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
TCC_DB_SYSTEM="/Library/Application Support/com.apple.TCC/TCC.db"

# Check Camera permission
# auth_value = 2 means granted, 0 means denied
CAMERA_GRANTED="0"
if [ -f "$TCC_DB_USER" ]; then
  CAMERA_RESULT=$(sqlite3 "$TCC_DB_USER" "SELECT auth_value FROM access WHERE service='kTCCServiceCamera' AND client='$BUNDLE_ID';" 2>/dev/null)
  if [ "$CAMERA_RESULT" = "2" ]; then
    CAMERA_GRANTED="1"
  fi
fi

if [ "$CAMERA_GRANTED" = "0" ] && [ -f "$TCC_DB_SYSTEM" ]; then
  CAMERA_RESULT=$(sqlite3 "$TCC_DB_SYSTEM" "SELECT auth_value FROM access WHERE service='kTCCServiceCamera' AND client='$BUNDLE_ID';" 2>/dev/null)
  if [ "$CAMERA_RESULT" = "2" ]; then
    CAMERA_GRANTED="1"
  fi
fi

# Check Microphone permission
# auth_value = 2 means granted, 0 means denied
MICROPHONE_GRANTED="0"
if [ -f "$TCC_DB_USER" ]; then
  MIC_RESULT=$(sqlite3 "$TCC_DB_USER" "SELECT auth_value FROM access WHERE service='kTCCServiceMicrophone' AND client='$BUNDLE_ID';" 2>/dev/null)
  if [ "$MIC_RESULT" = "2" ]; then
    MICROPHONE_GRANTED="1"
  fi
fi

if [ "$MICROPHONE_GRANTED" = "0" ] && [ -f "$TCC_DB_SYSTEM" ]; then
  MIC_RESULT=$(sqlite3 "$TCC_DB_SYSTEM" "SELECT auth_value FROM access WHERE service='kTCCServiceMicrophone' AND client='$BUNDLE_ID';" 2>/dev/null)
  if [ "$MIC_RESULT" = "2" ]; then
    MICROPHONE_GRANTED="1"
  fi
fi

# Output JSON format
echo "{\"bundleId\":\"$BUNDLE_ID\",\"camera\":$CAMERA_GRANTED,\"microphone\":$MICROPHONE_GRANTED}"

