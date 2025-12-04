FROM node:18-alpine

WORKDIR /app

# 安装官方 Filesystem MCP Server（全局）
RUN npm install -g @modelcontextprotocol/server-filesystem

# 更清晰的入口点设置
ENTRYPOINT ["npx", "@modelcontextprotocol/server-filesystem"]
CMD ["/ideaprojects", "/privategit", "/Downloads"]

EXPOSE 4000
 
# docker run -i --rm --mount type=bind,src=D://IdeaProjects,dst=/ideaprojects --mount type=bind,src=D://privategit,dst=/privategit -p 4000:4000 mcp/filesystem /ideaprojects /privategit