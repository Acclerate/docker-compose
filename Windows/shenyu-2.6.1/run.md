### Apache ShenYu 网关 (2.6.1)

> 官方部署文档：https://shenyu.apache.org/zh/docs/deployment/deployment-docker-compose
> 参考同级目录 `../shenyu`（2.7.0.3）的编排，本编排针对 **2.6.1（JDK 8 + Spring Boot 2.5.x）** 调整。

本编排复用**已存在的 MySQL 容器**（`mysql57`，MySQL 5.7，root/root，网络 `mysql_default`，
见 `../mysql` 下编排），仅启动 `shenyu-admin` 与 `shenyu-bootstrap`。配置文件已从 2.6.1 镜像导出到
`shenyu-admin/conf`、`shenyu-bootstrap/conf`，`mysql-connector.jar` 已放入 `shenyu-admin/ext-lib`。

#### 与 2.7.0.3 (`../shenyu`) 的关键差异

| 项 | 2.6.1（本目录）| 2.7.0.3（`../shenyu`）|
|---|---|---|
| 镜像 tag | `apache/shenyu-admin:2.6.1` / `bootstrap:2.6.1` | `2.7.0.3` |
| 运行时 | JDK 8 + Spring Boot 2.5.x | JDK 17 + Spring Boot 3.3.1 |
| 容器名 | `shenyu-admin-261` / `shenyu-bootstrap-261` | `shenyu-admin` / `shenyu-bootstrap` |
| 宿主机端口 | `9096:9095` / `9196:9195` | `9095:9095` / `9195:9195` |
| 数据库 | `shenyu_261`（独立库）| `shenyu` |
| 网络 | `shenyu_net_261` | `shenyu_net` |
| **mysql 驱动加载** | **用镜像默认 entrypoint**，ext-lib 进 `-classpath` 后 SB 2.x classloader 正常扫描，无需 hack | 需覆盖 entrypoint 把 ext-lib jar 复制到 lib/（SB 3.3.1 classloader 不扫描 ext-lib）|
| 是否可并存 | ✅ 两版本容器名/端口/网络/库全隔离，可同时运行 | — |

> ✅ **可与 `../shenyu`（2.7.0.3）同时运行**：端口（9096/9196 vs 9095/9195）、容器名（-261 后缀）、
> 网络（shenyu_net_261 vs shenyu_net）、数据库（shenyu_261 vs shenyu）全部错开。

#### 前置条件

1. 先启动 MySQL（若未启动）。本编排复用已存在的 `mysql57` 容器：

   ```shell
   docker start mysql57   # 或在 ../mysql 目录用 docker-compose 启动
   ```

2. **手动初始化数据库**（重要）：ShenYu 2.6.1 镜像内**只内置 h2 的 schema**
   （`sql-script/h2/schema.sql`），mysql 建表脚本不在镜像内，需手动导入。
   脚本已从官方仓库 2.6.1 tag 下载到 `shenyu-admin/db-init/schema.sql`
   （来源：`https://raw.githubusercontent.com/apache/shenyu/v2.6.1/db/init/mysql/schema.sql`），
   库名已改为 `shenyu_261` 以与 2.7.0.3 的 `shenyu` 库隔离：

   ```shell
   docker exec -i mysql57 mysql -uroot -proot < shenyu-admin/db-init/schema.sql
   # 验证：应看到 34 张表
   docker exec mysql57 mysql -uroot -proot -e "USE shenyu_261; SHOW TABLES;"
   ```

   > 重新生成 schema.sql（镜像升级时，2.6.1 镜像内无 mysql 脚本，须从官方仓库对应 tag 下载）：
   > ```shell
   > curl -L https://raw.githubusercontent.com/apache/shenyu/v2.6.1/db/init/mysql/schema.sql -o shenyu-admin/db-init/schema.sql
   > # 如需独立库，执行：sed -i 's/`shenyu`/`shenyu_261`/g' shenyu-admin/db-init/schema.sql
   > ```

#### 启动

```shell
docker-compose -f docker-compose-ShenYu.yaml -p shenyu261 up -d
```

> `-p shenyu261` 指定项目名，避免与其他 compose 项目冲突。
>
> ⚠️ 镜像拉取提示：`apache/shenyu-admin` 镜像较大，国内从 Docker Hub 拉取可能很慢或被 Aliyun 等镜像加速器返回 403。
> 若 `docker pull apache/shenyu-admin:2.6.1` 卡住，可改用镜像源拉取后重新打 tag：
> ```shell
> docker pull docker.m.daocloud.io/apache/shenyu-admin:2.6.1
> docker tag  docker.m.daocloud.io/apache/shenyu-admin:2.6.1 apache/shenyu-admin:2.6.1
> ```
> （`shenyu-bootstrap` 镜像同理。）

> ⚠️ **MySQL 驱动说明**：2.6.1 镜像内**不含** mysql 驱动，`shenyu-admin/ext-lib/mysql-connector.jar`
> 是必需的。与 2.7.0.3 不同，2.6.1 基于 Spring Boot 2.x，镜像默认 entrypoint 把 `ext-lib`
> 加入 `-classpath` 后，传统 classloader 会正常扫描加载驱动，**无需** 2.7.0.3 那样复制到 lib/ 的 hack。

#### 访问地址

- 管理后台（admin）：[`http://127.0.0.1:9096`](http://127.0.0.1:9096)
- 网关入口（bootstrap）：`http://127.0.0.1:9196`

默认登录账号密码：`admin / 123456`

> ⚠️ **登录失败排查**：ShenYu admin 首页 HTML 会注入一个隐藏的 `<div id="httpPath">`，
> 前端用它作为所有 API 请求的 baseURL。默认值是 admin 容器的**内网 IP**（如 `172.x.x.x`），
> 宿主机浏览器无法访问，表现为点登录无反应/请求超时。
>
> compose 中已通过 `ADMIN_JVM` 注入 `-Dshenyu.httpPath=.`，让前端走**相对路径**
> （自动使用浏览器当前访问的 host），本机 / 局域网 / 公网访问都正常。
>
> 若需改为固定地址（如远程访问），编辑 `docker-compose-ShenYu.yaml` 中：
> ```yaml
> - ADMIN_JVM=-server -Xmx2g -Xms2g -Xmn1g -Xss328k -Dshenyu.httpPath=你的IP或域名:9095
> ```
> （注意：该值会被前端当作 URL 拼接，所以"相对路径"用 `.` 最通用，不要写 `127.0.0.1:9095`。）

#### 常用命令

```shell
# 查看日志
docker logs -f shenyu-admin-261
docker logs -f shenyu-bootstrap-261

# 停止
docker-compose -f docker-compose-ShenYu.yaml -p shenyu261 down

# 健康检查
curl http://127.0.0.1:9096/actuator/health   # admin，期望 {"status":"UP",...}
curl http://127.0.0.1:9196/actuator/health   # bootstrap，期望 {"status":"UP",...}
```

#### 配置修改

- **数据源（JDBC 地址 / 账号密码）**：`shenyu-admin/conf/application-mysql.yml`
  - 默认连接 `mysql57:3306/shenyu_261`（通过外部网络 `mysql_default` 用容器名直连，root/root）。
  - 想换其他 MySQL：改 `url`/`username`/`password`，并确保容器能解析到目标地址
    （同 compose 用容器名，外部 MySQL 用 `host.docker.internal` 或加入目标网络）。
- **切换数据源类型**：`shenyu-admin/conf/application.yml` 中 `spring.profiles.active`
  （可选 `h2` / `mysql` / `pg` / `oracle` / `og`，默认已改为 `mysql`）。
- **bootstrap 与 admin 的同步方式**：`shenyu-bootstrap/conf/application.yml` 的 `shenyu.sync.websocket.urls`
  （默认 `ws://shenyu-admin-261:9095/websocket`，同 compose 内走容器名）。
- **mysql 驱动升级**：替换 `shenyu-admin/ext-lib/mysql-connector.jar` 即可，重启容器生效。

#### 目录结构

```
shenyu-2.6.1/
├── docker-compose-ShenYu.yaml
├── run.md
├── shenyu-admin/
│   ├── conf/                  # 从 2.6.1 镜像导出，已改 profiles=mysql
│   │   ├── application.yml
│   │   ├── application-mysql.yml   # 已改指向 mysql57/shenyu_261
│   │   └── ... (h2/pg/oracle/og + logback)
│   ├── db-init/
│   │   └── schema.sql         # 2.6.1 mysql 建表脚本，库名 shenyu_261
│   ├── ext-lib/
│   │   └── mysql-connector.jar
│   └── logs/
└── shenyu-bootstrap/
    ├── conf/                  # 从 2.6.1 镜像导出，已改 websocket urls
    │   ├── application.yml
    │   └── logback.xml
    └── logs/
```
