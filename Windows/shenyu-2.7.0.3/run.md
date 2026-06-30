### Apache ShenYu 网关 (2.7.0.3)

> 官方部署文档：https://shenyu.apache.org/zh/docs/deployment/deployment-docker-compose

本编排复用**已存在的 MySQL 容器**（见 `Windows/mysql/docker-compose-mysql8.0.yml`，宿主机端口 `3309`，root/root），
仅启动 `shenyu-admin` 与 `shenyu-bootstrap`。配置文件已下载到 `shenyu-admin/conf`、`shenyu-bootstrap/conf`，
`mysql-connector.jar` 已放入 `shenyu-admin/ext-lib`。

#### 前置条件

1. 先启动 MySQL（若未启动）。本编排复用已存在的 `mysql57` 容器（MySQL 5.7，root/root，
   网络 `mysql_default`，见 `Windows/mysql` 下编排）：

   ```shell
   docker start mysql57   # 或在 mysql 目录用 docker-compose 启动
   ```

2. **手动初始化数据库**（重要）：ShenYu 2.7.0.3 的官方 `application-mysql.yml` 未配置
   `init_script`，且镜像内只内置了 h2 的 schema（`sql-script/h2/schema.sql`），
   mysql 的建表脚本在镜像内 `/opt/shenyu-admin/db/init/mysql/schema.sql`，**不会自动执行**。
   因此首次部署必须手动导入。脚本已从镜像导出至 `shenyu-admin/db-init/schema.sql`：

   ```shell
   # schema.sql 顶部已含 CREATE DATABASE，库名 shenyu
   docker exec -i mysql57 mysql -uroot -proot < shenyu-admin/db-init/schema.sql
   # 验证：应看到 45+ 张表
   docker exec mysql57 mysql -uroot -proot -e "USE shenyu; SHOW TABLES;"
   ```

   > 重新生成 schema.sql（镜像升级时）：`docker run --rm --entrypoint sh apache/shenyu-admin:2.7.0.3 -c 'cat /opt/shenyu-admin/db/init/mysql/schema.sql' > shenyu-admin/db-init/schema.sql`

#### 启动

```shell
docker-compose -f docker-compose-ShenYu.yaml -p shenyu up -d
```

> ⚠️ 镜像拉取提示：`apache/shenyu-admin` 镜像较大（~1.3GB），国内从 Docker Hub 拉取可能很慢或被 Aliyun 等镜像加速器返回 403。
> 若 `docker pull apache/shenyu-admin:2.7.0.3` 卡在 `Pulling fs layer`，可改用可用的镜像源拉取后重新打 tag：
> ```shell
> docker pull docker.m.daocloud.io/apache/shenyu-admin:2.7.0.3
> docker tag  docker.m.daocloud.io/apache/shenyu-admin:2.7.0.3 apache/shenyu-admin:2.7.0.3
> ```
> （`shenyu-bootstrap` 镜像同理。）

> ⚠️ MySQL 驱动说明：镜像内**不含** mysql 驱动，`shenyu-admin/ext-lib/mysql-connector.jar`
> 是必需的。由于 ShenYu 2.7.0.3 的 entrypoint 把 `ext-lib` 加进 `-classpath` 后，
> Spring Boot 3.3.1 的 classloader 不会扫描它，compose 中已用自定义 entrypoint
> 启动前把 `ext-lib/*.jar` 复制到 `lib/`（Spring Boot 能扫描）来规避。

#### 访问地址

- 管理后台（admin）：[`http://127.0.0.1:9095`](http://127.0.0.1:9095)
- 网关入口（bootstrap）：`http://127.0.0.1:9195`

默认登录账号密码：`admin / 123456`

> ⚠️ **登录失败排查**：ShenYu admin 首页 HTML 会注入一个隐藏的
> `<div id="httpPath">`，前端用它作为所有 API 请求的 baseURL。默认值是 admin 容器的
> **内网 IP**（如 `172.28.0.2:9095`），宿主机浏览器无法访问，表现为点登录无反应/请求超时。
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
docker logs -f shenyu-admin
docker logs -f shenyu-bootstrap

# 停止
docker-compose -f docker-compose-ShenYu.yaml -p shenyu down
```

#### 配置修改

- 数据源（JDBC 地址 / 账号密码）：`shenyu-admin/conf/application-mysql.yml`
  - 默认连接 `host.docker.internal:3309`（Docker Desktop 下指向宿主机，无需改动）。
  - **Linux 环境**：`host.docker.internal` 已通过 `extra_hosts` 映射到 `host-gateway`；如连接失败，
    可改成宿主机真实 IP，或把 shenyu 容器加入 mysql 所在网络后改用容器名 `mysql8:3306`。
- 切换数据源类型：`shenyu-admin/conf/application.yml` 中 `spring.profiles.active`
  （可选 `h2` / `mysql` / `pg`，默认已改为 `mysql`）。
- bootstrap 与 admin 的同步方式：`shenyu-bootstrap/conf/application.yml` 的 `shenyu.sync.websocket.urls`
  （默认 `ws://shenyu-admin:9095/websocket`，同 compose 内走容器名）。
