import os
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()
print("key 读到了吗:", "是" if os.getenv("DEEPSEEK_API_KEY") else "否，检查 .env 文件")

client = OpenAI(
    api_key=os.getenv("DEEPSEEK_API_KEY"),
    base_url="https://api.deepseek.com",
)

resp = client.chat.completions.create(
    model="deepseek-v4-flash",
    messages=[{"role": "user", "content": "用一句话解释什么是市盈率"}],
)

print(resp.choices[0].message.content)
print(resp.usage)
