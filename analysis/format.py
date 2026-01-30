import subprocess
import os
import sys

# --- CONFIGURATION ---
ADB_CMD = "adb"  # Ensure adb is in your PATH

def check_adb_connection():
    """Verifies device connection."""
    try:
        result = subprocess.run([ADB_CMD, 'get-state'], 
                              capture_output=True, text=True, check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False

def get_android_version():
    """Fetches the Android version number dynamically."""
    try:
        # 'ro.build.version.release' is the standard property for OS version
        result = subprocess.run(
            [ADB_CMD, 'shell', 'getprop', 'ro.build.version.release'],
            capture_output=True, text=True, check=True
        )
        version = result.stdout.strip()
        
        # If empty or failed, fallback to 'Unknown'
        return version if version else "Unknown"
    except Exception:
        return "Unknown"

def get_raw_notifications():
    """Dumps the full unredacted notification stream."""
    try:
        print(">> Fetching raw notification data...")
        result = subprocess.run(
            [ADB_CMD, 'shell', 'dumpsys', 'notification', '--noredact'],
            capture_output=True, text=True, encoding='utf-8', errors='ignore'
        )
        return result.stdout
    except Exception as e:
        print(f"Error fetching data: {e}")
        return None

def main():
    print("--- 🕵️ ANDROID FORMAT SCANNER ---")
    
    # 1. Check Connection
    if not check_adb_connection():
        print("❌ Error: No device found. Please connect your phone via USB.")
        sys.exit(1)

    # 2. Detect Version
    version = get_android_version()
    print(f"✅ Detected Device: Android {version}")

    # 3. Create Dynamic Filename
    filename = f"Android_{version}_Notification_Format.txt"
    
    # 4. Fetch Data
    raw_data = get_raw_notifications()
    
    if raw_data:
        # 5. Save to File
        with open(filename, "w", encoding="utf-8") as f:
            f.write(raw_data)
        
        print(f"\n✅ SUCCESS! Raw format saved to:")
        print(f"   📂 {os.path.abspath(filename)}")
        print("\nYou can now open this file to inspect the 'Bundle' structure.")
    else:
        print("❌ Failed to retrieve notification data.")

if __name__ == "__main__":
    main()