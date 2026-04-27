# Apache Doris 4.0.5 Docker 离线部署教程

> 目标：在无网络的内网 Linux 服务器上，通过离线镜像部署 Apache Doris 4.0.5 单节点集群

---

## 整体流程

```
Windows 有网机器                    Linux 内网服务器
┌─────────────────┐                ┌─────────────────┐
│  docker pull    │                │                 │
│       ↓         │    U盘/scp     │  docker load    │
│  docker save    │ ──────────────→│       ↓         │
│  导出 tar 文件   │   传输文件      │  docker-compose │
│  + 配置文件      │                │       ↓         │
│                 │                │  启动并验证      │
└─────────────────┘                └─────────────────┘
```

---

## 第一阶段：Windows 准备（需要网络）

### 1.1 拉取镜像

```bash
docker pull apache/doris:fe-4.0.5
docker pull apache/doris:be-4.0.5
```

> 镜像大小参考：FE ≈ 1.3GB，BE ≈ 2.5GB（压缩后 tar 更小）

### 1.2 导出镜像

```bash
cd D:\privategit\gitee\docker-compose\Windows\doris\4.0.5

docker save apache/doris:fe-4.0.5 -o doris-fe-4.0.5.tar
docker save apache/doris:be-4.0.5 -o doris-be-4.0.5.tar
```

### 1.3 准备服务器配置文件

在 `Linux/doris/4.0.5/` 目录下准备以下文件：

#### 目录结构

```
Linux/doris/4.0.5/
├── docker-compose.yml
├── fe/
│   └── conf/
│       └── fe.conf
├── be/
│   └── conf/
│       └── be.conf
├── doris-fe-4.0.5.tar    # 从 Windows 拷贝
├── doris-be-4.0.5.tar    # 从 Windows 拷贝
└── run.md                # 部署操作说明
```

#### docker-compose.yml

```yaml
services:
  doris-fe:
    image: apache/doris:fe-4.0.5
    container_name: doris-fe
    hostname: doris-fe
    restart: unless-stopped
    environment:
      TZ: Asia/Shanghai
      FE_SERVERS: "fe1:172.30.80.2:9010"
      FE_ID: 1
    ports:
      - "8030:8030"   # FE HTTP WebUI
      - "9030:9030"   # MySQL 协议
      - "9010:9010"   # FE Edit Log
      - "9020:9020"   # FE RPC
      - "9090:9090"   # Arrow Flight SQL
    volumes:
      - ./fe/conf/fe.conf:/opt/apache-doris/fe/conf/fe.conf:z
      - ./fe/doris-meta:/opt/apache-doris/fe/doris-meta:Z
      - ./fe/log:/opt/apache-doris/fe/log:z
    networks:
      doris-net:
        ipv4_address: 172.30.80.2
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    mem_limit: 8g
    cpus: 4
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8030/api/bootstrap | grep -q '\"code\":0'"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  doris-be:
    image: apache/doris:be-4.0.5
    container_name: doris-be
    hostname: doris-be
    restart: unless-stopped
    depends_on:
      doris-fe:
        condition: service_healthy
    environment:
      TZ: Asia/Shanghai
      FE_SERVERS: "fe1:172.30.80.2:9010"
      BE_ADDR: "172.30.80.3:9050"
    ports:
      - "8040:8040"   # BE WebUI
      - "9050:9050"   # BE 心跳
      - "9060:9060"   # BE Thrift
      - "8060:8060"   # BE brpc
    volumes:
      - ./be/conf/be.conf:/opt/apache-doris/be/conf/be.conf:z
      - ./be/storage:/opt/apache-doris/be/storage:Z
      - ./be/log:/opt/apache-doris/be/log:z
    networks:
      doris-net:
        ipv4_address: 172.30.80.3
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
      memlock:
        soft: -1
        hard: -1
    mem_limit: 16g
    cpus: 8
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8040/api/health | grep -qi 'ok'"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 120s

networks:
  doris-net:
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 172.30.80.0/24
```

> **关键点：**
> - SELinux 标签：数据目录用 `:Z`（专属），配置/日志用 `:z`（共享）
> - 子网选 `172.30.80.0/24` 降低冲突概率，需与 fe.conf / be.conf 中 `priority_networks` 一致
> - 如果服务器子网冲突，需同时修改 docker-compose.yml、fe.conf、be.conf 三处

#### fe/conf/fe.conf

```ini
##====================================================================
## Apache Doris FE Configuration (Doris 4.0.5 / Linux Server)
## 适配：8核 32GB（FE 分配 4核 8GB）
##====================================================================

#------------ 元数据与日志 ------------
LOG_DIR = ${DORIS_HOME}/log
meta_dir = ${DORIS_HOME}/doris-meta

#------------ 网络绑定 ------------
priority_networks = 172.30.80.0/24

#------------ JVM 配置 ------------
JAVA_OPTS = "-Xmx6144m -Xms4096m"
JAVA_OPTS_FOR_JDK_17 = "-Xmx6144m -Xms4096m --add-opens=java.base/java.nio=ALL-UNNAMED"

#------------ 端口 ------------
http_port = 8030
rpc_port = 9020
query_port = 9030
edit_log_port = 9010
arrow_flight_sql_port = 9090

#------------ 查询优化 ------------
query_max_memory = 4294967296

#------------ 外部访问 ------------
enable_http_server_v2 = true

#------------ 日志级别 ------------
sys_log_level = INFO
```

#### be/conf/be.conf

```ini
##====================================================================
## Apache Doris BE Configuration (Doris 4.0.5 / Linux Server)
## 适配：8核 32GB（BE 分配 8核 16GB）
##====================================================================

#------------ 数据与日志 ------------
LOG_DIR = ${DORIS_HOME}/log
storage_root_path = ${DORIS_HOME}/storage

#------------ 网络绑定 ------------
priority_networks = 172.30.80.0/24

#------------ 端口 ------------
be_port = 9060
webserver_port = 8040
heartbeat_service_port = 9050
brpc_port = 8060

#------------ 内存限制 ------------
mem_limit = 12884901888

#------------ 并发与线程 ------------
tablet_map_shard_size = 8
default_num_parallel_load = 8
num_threads = 8

#------------ Compaction ------------
compaction_task_num_per_disk = 4
compaction_task_num_per_fast_disk = 4

#------------ 日志级别 ------------
sys_log_level = INFO
```

### 1.4 需要传输到服务器的文件清单

```
传输整个 Linux/doris/4.0.5/ 目录，包含：
  ├── docker-compose.yml          （部署编排）
  ├── fe/conf/fe.conf             （FE 配置）
  ├── be/conf/be.conf             （BE 配置）
  ├── doris-fe-4.0.5.tar          （FE 镜像，≈1.3GB）
  └── doris-be-4.0.5.tar          （BE 镜像，≈2.5GB）
```

---

## 第二阶段：服务器部署（无需网络）

### 2.1 安装 Docker 和 docker-compose

如果服务器已安装可跳过。Kylin V10 参考命令：

```bash
# 安装 Docker
yum install -y docker

# 安装 docker-compose（离线方式：提前下载二进制文件传入）
cp docker-compose-Linux-x86_64 /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# 启动 Docker
systemctl enable docker && systemctl start docker

# 验证
docker --version
docker-compose --version
```

### 2.2 放置文件

```bash
# 创建部署目录
mkdir -p /opt/doris/4.0.5

# 将传输的文件放入该目录，最终结构：
# /opt/doris/4.0.5/
#   ├── docker-compose.yml
#   ├── fe/conf/fe.conf     ← 必须是文件，不能是目录
#   ├── be/conf/be.conf     ← 必须是文件，不能是目录
#   ├── doris-fe-4.0.5.tar
#   └── doris-be-4.0.5.tar

cd /opt/doris/4.0.5
```

> **注意：** `fe/conf/fe.conf` 和 `be/conf/be.conf` 必须是**文件**，不能用 `mkdir` 创建（否则 docker-compose 会把目录挂载进去导致启动失败）。验证方法：`file fe/conf/fe.conf` 应显示 "ASCII text"，而非 "directory"。

### 2.3 导入镜像

```bash
docker load -i doris-fe-4.0.5.tar
docker load -i doris-be-4.0.5.tar

# 验证
docker images | grep doris
# 应显示：
#   apache/doris  fe-4.0.5  ...
#   apache/doris  be-4.0.5  ...
```

### 2.4 创建数据目录并启动

```bash
mkdir -p fe/doris-meta fe/log be/storage be/log

docker-compose up -d
```

### 2.5 等待启动并验证

```bash
# 等待 2-3 分钟后检查状态，两个容器都应 healthy
docker-compose ps

# 期望输出：
#   doris-fe   ... Up X minutes (healthy)   ...
#   doris-be   ... Up X minutes (healthy)   ...
```

### 2.6 设置 root 密码

```bash
# 首次启动后执行一次（单引号包裹防止 bash 解析特殊字符）
docker exec doris-fe mysql -uroot -h127.0.0.1 -P9030 -e 'ALTER USER "root" IDENTIFIED BY "你的密码";'
```

### 2.7 验证集群状态

```bash
# 验证 BE 已注册且存活（Alive 应为 true）
docker exec doris-fe mysql -uroot -h127.0.0.1 -P9030 -p'你的密码' -e "SHOW BACKENDS;"
```

### 2.8 建库建表测试

```bash
docker exec doris-fe mysql -uroot -h127.0.0.1 -P9030 -p'你的密码' -e "
CREATE DATABASE IF NOT EXISTS test_db;
USE test_db;
CREATE TABLE IF NOT EXISTS demo (
  id INT,
  name VARCHAR(50),
  age INT,
  created_at DATETIME
)
DISTRIBUTED BY HASH(id) BUCKETS 4
PROPERTIES ('replication_num' = '1');

INSERT INTO demo VALUES
  (1, 'Alice', 28, NOW()),
  (2, 'Bob', 35, NOW()),
  (3, 'Charlie', 22, NOW());

SELECT * FROM demo;
SELECT COUNT(*) AS total FROM demo;
"

# 测试完成后清理
docker exec doris-fe mysql -uroot -h127.0.0.1 -P9030 -p'你的密码' -e "DROP DATABASE IF EXISTS test_db;"
```

---

## 访问方式

| 服务 | 地址 |
|------|------|
| FE WebUI | http://服务器IP:8030 |
| MySQL 连接 | `mysql -h服务器IP -P9030 -uroot -p'密码'` |
| BE WebUI | http://服务器IP:8040 |

---

## 资源分配

| 组件 | CPU | 内存 | 说明 |
|------|-----|------|------|
| FE | 4 核 | 8 GB | JVM 堆 6GB |
| BE | 8 核 | 16 GB | mem_limit 12GB |
| 合计 | 8 核 | 24 GB | 服务器 32GB，留 8GB 给系统 |

---

## 常用命令

```bash
# 启动
docker-compose up -d

# 停止
docker-compose down

# 查看状态
docker-compose ps

# 查看日志
docker logs doris-fe --tail 100
docker logs doris-be --tail 100

# 重启单个服务
docker-compose restart doris-be

# 完全清除（包括数据，谨慎使用）
docker-compose down -v
rm -rf fe/doris-meta/* fe/log/* be/storage/* be/log/*
```

---

## 子网冲突处理

如果 `docker-compose up -d` 报错 `Pool overlaps`，需同时修改以下 3 处（将 `172.30.80` 替换为新段）：

1. `docker-compose.yml` — `subnet`、`ipv4_address`（FE 和 BE）、`FE_SERVERS`、`BE_ADDR`
2. `fe/conf/fe.conf` — `priority_networks`
3. `be/conf/be.conf` — `priority_networks`

---

## 故障排查

**FE 启动失败：**
- 查看日志：`docker logs doris-fe --tail 100`
- 清除元数据重新启动：`rm -rf fe/doris-meta/*` → `docker-compose up -d`

**BE 无法注册到 FE：**
- 查看日志：`docker logs doris-be --tail 100`
- 检查网络：`docker exec doris-fe ping 172.30.80.3`

**配置文件挂载失败：**
- 确认 `fe/conf/fe.conf` 和 `be/conf/be.conf` 是文件而非目录：`file fe/conf/fe.conf`

**Windows Docker Desktop 部署额外注意事项：**
- 需要在 environment 中清除代理变量（`http_proxy: ""` 等），否则 FE Java 进程会启动失败
- Volume 挂载不需要 SELinux 标签（`:z`/`:Z`）
- 子网避免使用 `172.20.x.x`（Docker Desktop 默认网络占用）

---

## Windows 本地开发部署（参考）

Windows 版 docker-compose.yml 与 Linux 版的主要差异：

| 项目 | Windows | Linux |
|------|---------|-------|
| 代理变量 | 需要清空 `http_proxy` 等 | 不需要 |
| SELinux 标签 | 不需要 `:z`/`:Z` | 需要 |
| 子网 | `172.28.81.0/24` | `172.30.80.0/24` |
| FE 资源 | 2核 6GB | 4核 8GB |
| BE 资源 | 6核 12GB | 8核 16GB |
| JVM 堆 | 4GB | 6GB |
| BE mem_limit | 8GB | 12GB |
