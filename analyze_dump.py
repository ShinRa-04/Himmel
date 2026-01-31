import re

try:
    with open("notification_dump.txt", "r", encoding="utf-16") as f:
        content = f.read()
except UnicodeError:
    try:
        with open("notification_dump.txt", "r", encoding="utf-8") as f:
            content = f.read()
    except:
        with open("notification_dump.txt", "r", encoding="latin-1") as f:
            content = f.read()

records = content.split("NotificationRecord")
print(f"Found {len(records)} segments.")

for i, record in enumerate(records):
    if "Hello AI" in record:
        print(f"--- Record {i} (MATCH FOUND) ---")
        # Print first 2000 chars of relevant record to see pkg name
        print(record[:2000])
        print("----------------")
    elif "messaging" in record:  # Fallback
        print(f"--- Record {i} (Messaging related) ---")
        print(record[:500])
        print("----------------")
