FROM node:18-alpine

WORKDIR /app

# 安装依赖
RUN apk add --no-cache \
    chromium \
    nss \
    freetype \
    harfbuzz \
    ca-certificates \
    ttf-freefont

# 安装Playwright
RUN npm install -g playwright

# 安装最新版本
RUN npx -y @mzxrai/mcp-webresearch@latest


# 暴露端口
EXPOSE 8856

# 启动命令
CMD ["npm", "run", "dev"]

# 该镜像很大，很卡，需要优化
# docker build --pull=false -f Windows\ai\mcp\webresearch.Dockerfile -t webresearch:latest Windows\ai\mcp
# trae配置  
# { 
#   "mcpServers": { 
#     "Web Research": {
#       "command": "docker",
#       "args": [
#         "run",
#         "--rm",
#         "-i",
#         "-p", "8856:8856",
#         "webresearch",
#         "npm",
#         "run",
#         "dev"
#       ]
#     }
#   }
# }