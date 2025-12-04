FROM node:20-alpine

WORKDIR /app

# 安装官方 Context7 MCP Server（全局）
RUN npm install -g @upstash/context7-mcp@latest

# 暴露默认端口
EXPOSE 4000

# 设置入口点
ENTRYPOINT ["npx", "-y", "@upstash/context7-mcp@latest"]