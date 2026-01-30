import subprocess
import time
import re
import xml.etree.ElementTree as ET

def get_button_coordinates():
    """
    Dumps the current screen UI hierarchy and finds the coordinates 
    of the 'Send' button dynamically.
    """
    try:
        # 1. Dump the UI hierarchy to a file on the device
        subprocess.run(["adb", "shell", "uiautomator", "dump", "/sdcard/window_dump.xml"], 
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        # 2. Read the file content
        result = subprocess.run(["adb", "shell", "cat", "/sdcard/window_dump.xml"], 
                                capture_output=True, text=True)
        xml_data = result.stdout

        # 3. Parse XML to find the Send button
        # We look for common identifiers for the send button (description or resource ID)
        # "Send SMS" is standard for Google Messages. "Send" is common for others.
        patterns = ['content-desc="Send SMS"', 'content-desc="Send"', 'resource-id=".*send_button.*"']
        
        bounds_match = None
        
        # Simple regex search to find the bounds property based on patterns
        for pattern in patterns:
            match = re.search(f'{pattern}.*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml_data, re.IGNORECASE)
            if match:
                bounds_match = match
                break
        
        if bounds_match:
            x1, y1, x2, y2 = map(int, bounds_match.groups())
            # Calculate center point
            center_x = (x1 + x2) // 2
            center_y = (y1 + y2) // 2
            return center_x, center_y
            
        return None, None

    except Exception as e:
        print(f"[-] Error finding button: {e}")
        return None, None

def send_smart_sms():
    phone_number = input("Enter Recipient Number: ")
    message_body = input("Enter Message Body: ")

    print(f"[*] Opening SMS app...")
    
    # 1. Open App
    subprocess.run([
        "adb", "shell", "am", "start", 
        "-a", "android.intent.action.SENDTO", 
        "-d", f"sms:{phone_number}", 
        "--es", "sms_body", f'"{message_body}"'
    ], stdout=subprocess.DEVNULL)

    # 2. Wait for UI to load
    print("[*] Waiting for screen to load...")
    time.sleep(2) 

    # 3. Find the Send Button dynamically
    print("[*] Scanning screen for 'Send' button...")
    x, y = get_button_coordinates()

    if x and y:
        print(f"[+] Found Send button at ({x}, {y}). Clicking...")
        subprocess.run(["adb", "shell", "input", "tap", str(x), str(y)])
        print("[+] Message sent.")
    else:
        print("[-] Could not find the 'Send' button automatically.")
        print("    (Try ensuring the keyboard isn't hiding the button, or update the search patterns)")

if __name__ == "__main__":
    send_smart_sms()