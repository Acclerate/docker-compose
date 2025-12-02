# 使用本地已有的node:18-alpine镜像
FROM node:18-alpine

WORKDIR /app

# 安装官方 Filesystem MCP Server（全局）
RUN npm install -g @modelcontextprotocol/server-filesystem

# 使用全局安装后的可执行文件，而不是再走 npx
# 这里的几个路径是“容器内”允许访问的根目录
CMD ["mcp-server-filesystem", "/ideaprojects", "/privategit", "/Downloads"]

# MCP 通过 STDIO 通信，不需要暴露端口；EXPOSE 4000 可以去掉
# 如果你以后要搞 HTTP 模式再加
