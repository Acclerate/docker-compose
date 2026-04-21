# 多阶段构建: GitHub MCP Server (Go)
# 源码: https://github.com/github/github-mcp-server
# 替代已弃用的 @modelcontextprotocol/server-github (Node.js)

FROM golang:1.25.3-alpine AS build
ARG VERSION="dev"

WORKDIR /build

# 安装 git (go build 需要)
RUN apk add git

# 下载源码并构建
RUN git clone https://github.com/github/github-mcp-server.git . && \
    CGO_ENABLED=0 go build -ldflags="-s -w -X main.version=${VERSION} -X main.commit=$(git rev-parse HEAD) -X main.date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    -o /bin/github-mcp-server cmd/github-mcp-server/main.go

# 运行阶段: 使用轻量级基础镜像
FROM gcr.io/distroless/base-debian12

LABEL io.modelcontextprotocol.server.name="io.github.github/github-mcp-server"

WORKDIR /server
COPY --from=build /bin/github-mcp-server .

ENTRYPOINT ["/server/github-mcp-server"]
CMD ["stdio"]

# 构建镜像命令示例:
# docker build --build-arg HTTP_PROXY= --build-arg HTTPS_PROXY= -t mcp-github-serve -f gitHub_MCP.Dockerfile .

# 运行容器命令示例 (stdio 模式):
# docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN=github_pat_xxxxxxxxxxxxxxxx mcp-github-serve

# 运行容器命令示例 (HTTP 模式):
# docker run -d --name mcp-github -p 4001:4001 -e GITHUB_PERSONAL_ACCESS_TOKEN=github_pat_xxxxxxxxxxxxxxxx mcp-github-serve --transport sse --port 4001 --address 0.0.0.0
