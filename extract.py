import json
import os
import re
import sys

from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()

client = OpenAI(
    api_key=os.getenv("DEEPSEEK_API_KEY"),
    base_url="https://api.deepseek.com",
)

# 用法：python extract.py data/bank_600036.txt
path = sys.argv[1] if len(sys.argv) > 1 else "data/sample.txt"

system_prompt = open("prompts/extract.txt", encoding="utf-8").read()
text = open(path, encoding="utf-8").read()

resp = client.chat.completions.create(
    model="deepseek-v4-flash",
    messages=[
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": text},
    ],
    temperature=0,
    max_tokens=800,
    response_format={"type": "json_object"},
)

raw = resp.choices[0].message.content
raw = re.sub(r"^```(?:json)?|```$", "", raw.strip(), flags=re.MULTILINE).strip()
result = json.loads(raw)

name = os.path.splitext(os.path.basename(path))[0]
os.makedirs("output", exist_ok=True)
out_path = f"output/{name}.json"

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(result, f, ensure_ascii=False, indent=2)

print(json.dumps(result, ensure_ascii=False, indent=2))
print("\n已保存:", out_path)
print("token 用量:", resp.usage.total_tokens)
