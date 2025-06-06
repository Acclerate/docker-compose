
FROM node:18-alpine

WORKDIR /app

# 安装指定版本的 npm
RUN npm install -g npm@10.2.0

# 安装编译工具（如果 figma-mcp 需要）
RUN apk add --no-cache python3 make g++

# 安装 figma-developer-mcp
RUN npm install -g figma-developer-mcp

# 清理不必要的依赖
RUN apk del python3 make g++

# 验证安装
RUN node -v && npm -v && figma-developer-mcp --version

CMD ["node"]

# docker build --pull=false -f Windows\ai\mcp\figma-mcp-server.Dockerfile -t figma-mcp-server:latest Windows\ai\mcp