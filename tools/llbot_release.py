import json, urllib.request, sys

url = "https://api.github.com/repos/LLOneBot/LuckyLilliaBot/releases/latest"
req = urllib.request.Request(url, headers={"User-Agent": "curl/8", "Accept": "application/vnd.github+json"})
try:
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.load(r)
except Exception as e:
    print("ERR", e)
    sys.exit(1)

print("tag:", data.get("tag_name"), "published:", data.get("published_at"))
for a in data.get("assets", []):
    print(f"{a['name']}\t{a['size']}\t{a['browser_download_url']}")
