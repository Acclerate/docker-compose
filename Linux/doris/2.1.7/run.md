### Apache Doris 2.1.7

> 环境：Kylin Linux Advanced Server release V10 (Halberd)  x86_64  8核32G
>
> 麒麟（Kylin）是国产操作系统，基于 Linux 内核，由麒麟软件有限公司研发，广泛应用于党政军及关键信息基础设施领域。

---

## 目录结构

```
doris/2.1.7/
├── docker-compose.yml
├── fe/
│   ├── conf/
│   │   └── fe.conf        # FE 自定义配置（已针对 8核32G 优化）
│   ├── doris-meta/        # FE 元数据（自动创建，重要！）
│   └── log/               # FE 日志
└── be/
    ├── conf/
    │   └── be.conf        # BE 自定义配置（已针对 8核32G 优化）
    ├── storage/           # BE 数据文件（自动创建，重要！）
    └── log/               # BE 日志
```

---

## 系统前置要求（宿主机 — Kylin Linux Advanced Server V10）

> **关于麒麟系统：**
> **Kylin Linux Advanced Server release V10 (Halberd)** 是国产操作系统，由麒麟软件有限公司研发，
> 基于 Linux 内核（4.19 / 5.10），兼容 RHEL/CentOS 生态，广泛用于党政军及关键信息基础设施。
> 与 CentOS 7/8 相比，麒麟 V10 有以下**特有配置差异**，必须额外处理：
>
> | 特性 | CentOS 7 | **Kylin V10** |
> |------|---------|--------------|
> | SELinux | 默认 Enforcing | **默认 Enforcing，更严格** |
> | firewalld | 默认开启 | **默认开启** |
> | cgroup 版本 | v1 | **部分版本默认 cgroup v2** |
> | Docker 官方源 | 有 | **无，需借用 CentOS repo** |

---

### 第一步：安装 Docker（麒麟 V10 专用方式）

麒麟 V10 无官方 Docker 源，使用 CentOS 7 源安装：

```shell
# 安装依赖
dnf install -y yum-utils device-mapper-persistent-data lvm2

# 添加 Docker 的 CentOS 7 源（Kylin V10 兼容）
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# 安装 Docker Engine（若网络受限可替换为国内镜像源）
dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 启动并设置开机自启
systemctl enable --now docker
```

---

### 第二步：处理 SELinux（⚠️ 麒麟 V10 特有，必须处理）

麒麟 V10 默认 SELinux 为 **Enforcing** 模式，会导致容器无法访问宿主机挂载目录，出现 `Permission denied`。

**方案 A（推荐生产环境）：使用 SELinux 卷标签**

在 `docker-compose.yml` 各 volumes 挂载路径末尾加 `:z`（共享）或 `:Z`（私有），例如：

```yaml
volumes:
  - ./fe/conf/fe.conf:/opt/apache-doris/fe/conf/fe.conf:z
  - ./fe/doris-meta:/opt/apache-doris/fe/doris-meta:Z
```

**方案 B（开发/测试环境）：将 SELinux 切换为 Permissive**

```shell
# 临时生效（重启失效）
setenforce 0

# 永久生效（修改配置文件）
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# 验证
getenforce
# 输出: Permissive
```

> ⚠️ 不建议直接 `SELINUX=disabled`，在麒麟系统中切换 disabled 需重启，且可能影响系统安全合规要求。

---

### 第三步：处理 firewalld（⚠️ 麒麟 V10 特有，必须处理）

麒麟 V10 默认开启 firewalld，与 Docker iptables 规则可能冲突，导致容器间网络不通或端口无法访问。

**方案 A（推荐）：信任 Docker 网桥接口**

```shell
# 信任 docker0 接口（容器内网互通）
firewall-cmd --permanent --zone=trusted --add-interface=docker0
# 信任自定义 bridge（本 compose 使用的网络）
firewall-cmd --permanent --zone=trusted --add-interface=br-+

# 开放 Doris 对外服务端口
firewall-cmd --permanent --add-port=8030/tcp   # FE WebUI
firewall-cmd --permanent --add-port=9030/tcp   # FE MySQL 协议
firewall-cmd --permanent --add-port=8040/tcp   # BE WebUI

# 重载规则
firewall-cmd --reload
```

**方案 B（开发/测试环境）：直接关闭 firewalld**

```shell
systemctl stop firewalld
systemctl disable firewalld
```

---

### 第四步：检查并处理 cgroup 版本（⚠️ 麒麟 V10 SP2+ 可能默认 v2）

```shell
# 检查当前 cgroup 版本
stat -fc %T /sys/fs/cgroup/
# 输出 tmpfs  → cgroup v1（无需处理）
# 输出 cgroup2fs → cgroup v2（需要配置 Docker）
```

**若为 cgroup v2，配置 Docker 使用 systemd cgroup driver：**

```shell
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

systemctl daemon-reload
systemctl restart docker
```

**若 Docker 版本较旧（< 20.10）且无法升级，可降级回 cgroup v1：**

```shell
# 在 GRUB 配置中添加内核参数（/etc/default/grub）
# 在 GRUB_CMDLINE_LINUX 末尾追加 systemd.unified_cgroup_hierarchy=0
sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 systemd.unified_cgroup_hierarchy=0"/' /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
reboot
```

---

### 第五步：开启内核网络转发（Docker 网络必须）

```shell
# 加载 bridge 模块（麒麟 V10 有时需手动加载）
modprobe br_netfilter
echo "br_netfilter" >> /etc/modules-load.d/br_netfilter.conf

# 开启 IP 转发和 bridge iptables
cat >> /etc/sysctl.conf <<'EOF'
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl -p
```

---

### 第六步：Doris 专用内核参数

```shell
# 1. 关闭透明大页（THP）— 必须，否则 BE 启动警告并影响性能
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag

# 永久生效：写入 /etc/rc.local
cat >> /etc/rc.local <<'EOF'
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
EOF
chmod +x /etc/rc.local

# 2. 调整最大虚拟内存映射数（BE mmap 需要）
echo "vm.max_map_count=2000000" >> /etc/sysctl.conf
sysctl -p

# 3. 调整文件句柄数
cat >> /etc/security/limits.conf <<'EOF'
* soft nofile 65536
* hard nofile 65536
EOF

# 4. 时区设置
timedatectl set-timezone Asia/Shanghai
```

---

## 启动

```shell
docker-compose -f docker-compose.yml -p doris up -d
```

启动顺序：FE 先启动，BE 等待 FE 健康检查通过后再启动（约 60~120 秒）。

查看日志：

```shell
# 查看 FE 日志
docker logs -f doris-fe

# 查看 BE 日志
docker logs -f doris-be
```

---

## 验证

### 1. 检查节点状态

```shell
# 使用 MySQL 客户端连接 FE（默认 root 密码为空）
mysql -h 127.0.0.1 -P 9030 -u root

# 查看 FE 节点状态（Alive 为 true 表示正常）
SHOW FRONTENDS\G

# 查看 BE 节点状态（Alive 为 true 表示正常）
SHOW BACKENDS\G
```

### 2. WebUI 访问

| 组件 | 地址 | 说明 |
|------|------|------|
| FE WebUI | `http://宿主机IP:8030` | 默认账号：`root` / 空密码 |
| BE WebUI | `http://宿主机IP:8040` | 节点信息、Profile 分析 |

---

## 首次登录修改 root 密码（建议）

```sql
-- 连接 FE 后执行
SET PASSWORD FOR 'root'@'%' = PASSWORD('your_password');
```

---

## 手动注册 BE（若容器启动后 BE 未自动注册）

```sql
-- 连接 FE 后执行，IP 为 BE 容器 IP
ALTER SYSTEM ADD BACKEND "172.20.80.3:9050";
```

验证：

```sql
SHOW BACKENDS\G
-- Alive: true 表示注册成功
```

---

## 停止与清理

```shell
# 停止
docker-compose -f docker-compose.yml -p doris down

# 停止并删除数据（⚠️ 不可逆）
docker-compose -f docker-compose.yml -p doris down -v
rm -rf ./fe/doris-meta ./fe/log ./be/storage ./be/log
```

---

## 关键配置说明

### fe.conf 关键参数

| 参数 | 值 | 说明 |
|------|----|------|
| `priority_networks` | `172.20.80.0/24` | FE 绑定的网段，需与 Docker 网络一致 |
| `JAVA_OPTS -Xmx` | `8192m` | FE JVM 最大堆，8核32G 推荐 6~8GB |
| `http_port` | `8030` | FE WebUI 端口 |
| `query_port` | `9030` | MySQL 协议端口 |
| `edit_log_port` | `9010` | FE 选主/元数据同步端口 |

### be.conf 关键参数

| 参数 | 值 | 说明 |
|------|----|------|
| `priority_networks` | `172.20.80.0/24` | BE 绑定的网段，需与 Docker 网络一致 |
| `mem_limit` | `16GB` | BE 内存上限，推荐物理内存的 50%~80% |
| `storage_root_path` | `/opt/apache-doris/be/storage` | 数据目录，多块磁盘用 `;` 分隔 |
| `pipeline_executor_size` | `8` | 执行线程数，建议等于 CPU 核心数 |
| `doris_scanner_thread_pool_thread_num` | `16` | 扫描线程数，建议 CPU 核心数 × 2 |

---

## 扩展：多块磁盘配置（be.conf）

```properties
# 多块磁盘提升 IO 并发，格式：路径[,类型[,容量GB]]
storage_root_path = /opt/apache-doris/be/storage1,SSD,200;/opt/apache-doris/be/storage2,HDD,500
```

并在 `docker-compose.yml` 对应 BE 的 volumes 中添加磁盘挂载。
