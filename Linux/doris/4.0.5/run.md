### Apache Doris 4.0.5 离线部署指南（Linux）
> 环境：Kylin Linux V10 x86_64 8核32G / 镜像从 Windows Docker Desktop 导出
> 默认配置可直接使用，无需修改

---

## 目录结构

```
4.0.5/
├── docker-compose.yml
├── fe/
│   ├── conf/fe.conf
│   ├── doris-meta/       # FE 元数据（自动创建，重要，必须持久化）
│   └── log/              # FE 日志
├── be/
│   ├── conf/be.conf
│   ├── storage/          # BE 数据存储（自动创建，重要，必须持久化）
│   └── log/              # BE 日志
├── doris-fe-4.0.5.tar    # FE 镜像文件（从导出机器拷贝）
├── doris-be-4.0.5.tar    # BE 镜像文件（从导出机器拷贝）
└── run.md                # 本文件
```

---

## 第一步：导入镜像

```bash
cd /opt/doris/4.0.5    # 或你实际放置的目录

docker load -i doris-fe-4.0.5.tar
docker load -i doris-be-4.0.5.tar

# 验证镜像已导入
docker images | grep doris
# 应显示：
#   apache/doris  fe-4.0.5  ...
#   apache/doris  be-4.0.5  ...
```

---

## 第二步：启动

```bash
# 创建必要目录
mkdir -p fe/doris-meta fe/log be/storage be/log

# 启动（FE 先启动，健康检查通过后自动启动 BE）
docker-compose up -d

# 查看状态
docker-compose ps
```

---

## 第三步：验证

```bash
# 1. 检查容器状态（等待约 2-3 分钟，两个都应 healthy）
docker ps --filter name=doris

# 2. 设置 root 密码（首次启动后执行一次）
docker exec doris-fe mysql -uroot -h127.0.0.1 -P9030 -e "ALTER USER 'root' IDENTIFIED BY 'YTybds1!';"

# 3. 验证密码生效
docker exec doris-fe mysql -uroot -p'YTybds1!' -h127.0.0.1 -P9030 -e "SHOW BACKENDS;"

# 4. 建库建表测试
docker exec doris-fe mysql -uroot -p'YTybds1!' -h127.0.0.1 -P9030 -e "
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

# 5. 测试完成后清理
docker exec doris-fe mysql -uroot -p'YTybds1!' -h127.0.0.1 -P9030 -e "DROP DATABASE IF EXISTS test_db;"
```

---

## 常用命令

```bash
# 启动
docker-compose up -d

# 停止
docker-compose down

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

## 访问方式

| 服务 | 地址 |
|------|------|
| FE WebUI | http://服务器IP:8030 （账号 `root` / 密码 `YTybds1!`） |
| MySQL 连接 | `mysql -h服务器IP -P9030 -uroot -p'YTybds1!'` |
| BE WebUI | http://服务器IP:8040 |

---

## 资源分配

| 组件 | CPU | 内存 | 说明 |
|------|-----|------|------|
| FE | 4 核 | 8 GB | JVM 堆 6GB |
| BE | 8 核 | 16 GB | mem_limit 12GB |
| 合计 | 8 核 | 24 GB | 服务器 32GB，留 8GB 给系统 |

---

## 故障排查

**FE 启动失败：**
- 检查 `fe/log/fe.log` 和 `fe/log/fe.out`
- 如果之前启动过，清除元数据：`rm -rf fe/doris-meta/*`，重新 `docker-compose up -d`

**BE 无法注册到 FE：**
- 检查网络配置：`docker exec doris-fe ping 172.30.80.3`
- 检查 BE 日志：`docker logs doris-be --tail 50`

**子网冲突（极少发生）：**
- `docker network ls` 查看已有网络
- 如果启动报错 `Pool overlaps`，需同时修改以下 3 处（保持一致，将 `172.30.80` 替换为你选的新段）：
  1. `docker-compose.yml` 中的 `subnet`、`ipv4_address`、`FE_SERVERS`、`BE_ADDR`
  2. `fe/conf/fe.conf` 中的 `priority_networks`
  3. `be/conf/be.conf` 中的 `priority_networks`
