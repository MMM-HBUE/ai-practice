# ai-practice

金融科技方向 AI 应用练习项目。

## 环境
- Python 3.15（虚拟环境 .venv，不纳入版本管理）
- DeepSeek API（Key 存于本地 .env，不提交）

## 内容
- hello.py —— DeepSeek API 连通性测试
- extract.py —— 财报指标抽取：读文本，输出 JSON 到 output/
- run.ps1 —— 实验运行器，每次运行归档到 runs/<时间戳>/

## 运行
.\run.ps1 extract.py data\sample.txt
