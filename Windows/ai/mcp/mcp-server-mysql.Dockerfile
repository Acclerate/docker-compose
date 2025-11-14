# Dockerfile for MySQL MCP Server
FROM node:18-alpine

WORKDIR /app

# 安装通用 SQL MCP 服务（假设包名为 @f4ww4z/mcp-server-mysql）
RUN npm install -g @f4ww4z/mcp-mysql-server

EXPOSE 4002

# 设置容器启动时运行的命令
CMD ["mcp-mysql", "--stdio"]


# docker run -d \
#   --name mcp-mysql \
#   -p 4002:4002 \
#   -e MYSQL_HOST=your.mysql.host \
#   -e MYSQL_PORT=3306 \
#   -e MYSQL_USER=root \
#   -e MYSQL_PASSWORD=root \
#   -e MYSQL_DATABASE=sc_mds_c \
#   -e ALLOWED_QUERIES="SELECT" \	# 可选：限制仅允许 SELECT
#   mcp-server-mysql