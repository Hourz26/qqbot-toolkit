import json, sys, io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from astrbot.core.config.default import CONFIG_METADATA_2
from astrbot.dashboard.services.config_service import validate_config

path = r"D:\Apps\astrbot\data\cmd_config.json"
with open(path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

errors, post = validate_config(cfg, CONFIG_METADATA_2, True, runtime={"os": "windows"})
print("ERROR COUNT:", len(errors))
for e in errors:
    print(" -", e)
