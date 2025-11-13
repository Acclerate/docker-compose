# 使用官方 Node.js 18 的 Alpine 镜像作为基础镜像
FROM node:18-alpine

# 设置工作目录
WORKDIR /app

# 全局安装 GitHub MCP 服务器
RUN npm install -g @modelcontextprotocol/server-github

# 验证安装并获取 binary 路径
RUN npm list -g @modelcontextprotocol/server-github
RUN echo "Global npm bin path: $(npm bin -g)"

# 创建一个本地目录并生成配置文件
RUN mkdir -p /app/data
RUN echo "{}" > /app/data/config.json

# 暴露默认端口（GitHub MCP 默认使用 4001）
EXPOSE 4001

# 启动命令：直接运行 GitHub MCP 服务器
# 注意：GITHUB_PERSONAL_ACCESS_TOKEN 需通过环境变量传入
CMD ["mcp-server-github"]

# docker run -d \
#   --name mcp-github \
#   -p 4000:4000 \
#   -e GITHUB_PERSONAL_ACCESS_TOKEN=your_github_personal_access_token_here \
#   mcp-github-server
