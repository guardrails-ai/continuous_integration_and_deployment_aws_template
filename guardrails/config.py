import json
import os
from guardrails import Guard
from guardrails.hub import DetectPII

try:
    file_path = os.path.join(os.getcwd(), "chatbot.json")
    with open(file_path, "r") as fin:
        guards = json.load(fin)["guards"] or []
except json.JSONDecodeError:
    print("Error parsing guards from JSON")
    SystemExit(1)

# instantiate guards
guard0 = Guard.from_dict(guards[0])
