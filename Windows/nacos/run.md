### Nacos

```shell
# 内嵌 Derby 库（最简，开箱即用）
docker-compose -f docker-compose-nacos.yml -p nacos up -d

# 1.4.1 + MySQL 版 【 需自己建库`nacos_config`, 并执行`nacos_1.4.1/nacos-mysql.sql`脚本 】
docker-compose -f docker-compose-nacos-1.4.1.yml -p nacos up -d

# 2.3.2 + MySQL 版（开启鉴权，默认对接 ShenYu 2.6.1）
#   【 需自己建库`nacos_config`, 并执行`nacos_2.3.2/nacos-mysql.sql`脚本（2.x 表结构含 encrypted_data_key，不可复用 1.x sql）】
docker-compose -f docker-compose-nacos-2.3.2.yml -p nacos up -d
```

访问地址：[`http://127.0.0.1:8848/nacos`](http://127.0.0.1:8848/nacos)
登录账号密码默认：`nacos/nacos`

> 注：`docker-compose-nacos-1.4.1-mysql.yml`已开启连接密码安全认证，在java连接时需新增配置如下

```yml
spring:
  cloud:
    nacos:
      discovery:
        username: nacos
        password: nacos
      config:
        username: ${spring.cloud.nacos.discovery.username}
        password: ${spring.cloud.nacos.discovery.password}
```

#### 2.3.2 说明（对接 ShenYu 2.6.1）

- **端口**：Nacos 2.x 新增 gRPC，`8848`(HTTP/OpenAPI) + `9848`(sdk gRPC，主端口+1000) + `9849`(集群 gRPC，主端口+1001)。Java 客户端走 gRPC，**`9848` 必须对外暴露**，否则连不上。
- **鉴权**：2.2.0+ 必须显式配置 `nacos.core.auth.plugin.nacos.token.secret.key`(Base64，原始 ≥32 字符) 与 `server.identity`，默认值会触发高危漏洞。本编排默认值与 ShenYu admin/bootstrap 的 `shenyu.sync.nacos` 默认值对齐，改其一需同步修改另一侧。
- **持久化**：推荐用 `spring.sql.init.platform=mysql`(`spring.datasource.platform` 已 deprecated)；`nacos-mysql.sql` 来自官方 2.3.2 `distribution/conf/mysql-schema.sql`，相对 1.x 新增 `encrypted_data_key` 字段。
- **版本一致性**：`nacos-client` 用 ShenYu 2.6.1 根 pom 锁定的 2.0.4，**不要**手动改成 2.3.x 客户端。