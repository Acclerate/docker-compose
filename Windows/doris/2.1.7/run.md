### Apache Doris 2.1.7 (Windows)

> 环境：Windows 11 Pro (Docker Desktop + WSL2) 宿主机 32GB / Docker 分配 8核23.5G

---

## 目录结构

```
Windows/doris/2.1.7/
├── docker-compose.yml      # Docker Compose 编排文件（已针对 Win11 Docker Desktop 优化）
├── fe/
│   ├── conf/
│   │   └── fe.conf         # FE 自定义配置（JVM 4GB 堆）
│   ├── doris-meta/         # FE 元数据（自动创建，重要！）
│   └── log/                # FE 日志
└── be/
    ├── conf/
    │   └── be.conf         # BE 自定义配置（mem_limit 8GB）
    ├── storage/            # BE 数据文件（自动创建，重要！）
    └── log/                # BE 日志
```

---

## 系统前置要求（Windows 11 + Docker Desktop）

### 第一步：确保 Docker Desktop 已安装并运行

1. 安装 [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/)
2. 确保 WSL2 后端已启用：
   ```powershell
   # 在 PowerShell（管理员）中执行
   wsl --install
   wsl --update
   ```
3. 启动 Docker Desktop，确认左下角显示 "Engine running"

### 第二步：配置 Docker Desktop 资源

在 Docker Desktop -> Settings -> Resources 中：

| 配置项 | 推荐值 | 说明 |
|--------|--------|------|
| CPUs | 8 | 分配给 Docker 的 CPU 核心数 |
| Memory | 23.5 GB | 分配给 Docker 的内存（32GB 宿主机推荐） |
| Swap | 4 GB | 交换空间 |
| Disk image size | 64 GB | 虚拟磁盘大小 |

> **注意**：修改后需点击 "Apply & Restart" 重启 Docker。

### 第三步：检查 WSL2 内核参数

Doris BE 对 `vm.max_map_count` 有要求（默认值可能不够）。在 PowerShell（管理员）中执行：

```powershell
# 创建/编辑 %USERPROFILE%\.wslconfig 文件
# 添加以下内容：
@"
[wsl2]
kernelCommandLine = vsyscall=emulate
"@
# 然后重启 WSL
wsl --shutdown
```

启动 WSL 后，在 WSL 终端中确认：
```bash
# 检查 max_map_count
sysctl vm.max_map_count
# 如果低于 2000000，需要在 WSL 中设置：
sudo sysctl -w vm.max_map_count=2000000
```

> **Windows 11 22H2+ 可通过 `.wslconfig` 持久化设置：**
> ```ini
> [wsl2]
> kernelCommandLine = sysctl.vm_max_map_count=2000000
> ```

---

## 启动

打开 PowerShell 或 Git Bash，进入本目录：

```shell
# 启动（-d 后台运行）
docker compose -f docker-compose.yml -p doris up -d
```

启动顺序：FE 先启动，BE 等待 FE 健康检查通过后再启动（约 60~120 秒）。

查看日志：

```shell
# 查看 FE 日志
docker logs -f doris-fe

# 查看 BE 日志
docker logs -f doris-be

# 查看容器状态
docker ps
```

---

## 验证

### 1. 检查容器状态

```shell
# 确认两个容器都是 healthy 状态
docker ps --format "table {{.Names}}\t{{.Status}}"
```

### 2. 使用 MySQL 客户端连接

```shell
# 进入 FE 容器内部使用 mysql 客户端
docker exec -it doris-fe mysql -h 127.0.0.1 -P 9030 -u root

# 或从宿主机使用 mysql 客户端（需已安装）
mysql -h 127.0.0.1 -P 9030 -u root
```

```sql
-- 查看 FE 节点状态（Alive 为 true 表示正常）
SHOW FRONTENDS\G

-- 查看 BE 节点状态（Alive 为 true 表示正常）
SHOW BACKENDS\G
```

### 3. WebUI 访问

| 组件 | 地址 | 说明 |
|------|------|------|
| FE WebUI | http://localhost:8030 | 默认账号：`root` / 空密码 |
| BE WebUI | http://localhost:8040 | 节点信息、Profile 分析 |

### 4. 创建测试数据库验证功能

```sql
-- 创建测试数据库
CREATE DATABASE test_db;
USE test_db;

-- 创建测试表
CREATE TABLE test_table (
    id INT,
    name VARCHAR(50),
    age INT,
    create_time DATETIME
)
DISTRIBUTED BY HASH(id) BUCKETS 4
PROPERTIES ("replication_num" = "1");

-- 插入测试数据
INSERT INTO test_table VALUES
(1, 'Alice', 30, '2024-01-01 10:00:00'),
(2, 'Bob', 25, '2024-01-02 11:00:00'),
(3, 'Charlie', 35, '2024-01-03 12:00:00');

-- 查询验证
SELECT * FROM test_table;
SELECT COUNT(*) FROM test_table;

-- 清理测试数据
DROP DATABASE test_db;
```

---

## 首次登录修改 root 密码（建议）

```sql
SET PASSWORD FOR 'root'@'%' = PASSWORD('your_password');
```

---

## 手动注册 BE（若容器启动后 BE 未自动注册）

```sql
ALTER SYSTEM ADD BACKEND "172.20.81.3:9050";
```

验证：

```sql
SHOW BACKENDS\G
-- Alive: true 表示注册成功
```

---

## 停止与清理

```shell
# 停止容器
docker compose -f docker-compose.yml -p doris down

# 停止并删除数据（⚠️ 不可逆）
docker compose -f docker-compose.yml -p doris down -v
rm -rf ./fe/doris-meta ./fe/log ./be/storage ./be/log
```

---

## 关键配置说明

### 资源分配策略（32GB 宿主机）

| 组件 | 容器内存 | 进程内存 | CPU | 说明 |
|------|---------|---------|-----|------|
| FE | 6 GB | JVM 堆 4 GB | 2 核 | 元数据管理、SQL 解析 |
| BE | 12 GB | mem_limit 8 GB | 6 核 | 数据存储、计算执行 |
| 合计 | 18 GB | 12 GB | 8 核 | Docker Desktop 分配 23.5 GB |

### fe.conf 关键参数

| 参数 | 值 | 说明 |
|------|----|------|
| `priority_networks` | `172.20.81.0/24` | FE 绑定网段，与 Docker 网络一致 |
| `JAVA_OPTS -Xmx` | `4096m` | JVM 最大堆，适配 6GB 容器 |
| `http_port` | `8030` | FE WebUI 端口 |
| `query_port` | `9030` | MySQL 协议端口 |

### be.conf 关键参数

| 参数 | 值 | 说明 |
|------|----|------|
| `priority_networks` | `172.20.81.0/24` | BE 绑定网段，与 Docker 网络一致 |
| `mem_limit` | `8GB` | BE 进程内存上限 |
| `pipeline_executor_size` | `6` | 执行线程数，等于分配的 CPU 核数 |
| `doris_scanner_thread_pool_thread_num` | `12` | 扫描线程数，CPU 核数 × 2 |

### 与 Linux 版本的差异

| 项目 | Linux 版 | Windows 版 | 原因 |
|------|---------|-----------|------|
| Docker 子网 | `172.20.80.0/24` | `172.20.81.0/24` | 避免与 Linux 版冲突 |
| Volume 标签 | `:z` / `:Z`（SELinux） | 无 | Windows 无 SELinux |
| FE JVM 堆 | `6144m` | `4096m` | Docker Desktop 可用内存较少 |
| BE mem_limit | `12GB` | `8GB` | Docker Desktop 可用内存较少 |
| FE 容器限制 | 4 核 8G | 2 核 6G | 需预留更多给宿主机 |
| BE 容器限制 | 8 核 16G | 6 核 12G | 需预留更多给宿主机 |

---

## 常见问题

### Q: BE 启动失败，日志报 `vm.max_map_count` 不足
```bash
# 在 WSL 终端中执行
sudo sysctl -w vm.max_map_count=2000000
# 然后重启容器
docker restart doris-be
```

### Q: 容器启动很慢
首次启动需要拉取镜像（约 2~3GB），请耐心等待。可使用国内镜像加速：
```json
// Docker Desktop -> Settings -> Docker Engine
{
  "registry-mirrors": ["https://mirror.ccs.tencentyun.com"]
}
```

### Q: 连接 MySQL 端口被拒绝
确认容器已健康启动：`docker ps` 查看 STATUS 列是否为 `healthy`。
