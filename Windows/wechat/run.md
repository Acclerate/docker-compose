### Docker 版微信（ricwang/docker-wechat）

> 在 Docker 里运行 Linux 版微信，通过 **浏览器（noVNC）** 或 **VNC 客户端** 访问。
> - 项目地址：https://github.com/RICwang/docker-wechat
> - 论坛教程：https://club.fnnas.com/forum.php?mod=viewthread&tid=31514

#### 一、启动

```shell
docker-compose -f docker-compose-wechat.yml -p wechat up -d
```

> 首次启动会自动拉取镜像（约 1.9GB）。
>
> ⚠️ **国内拉取 Docker Hub 容易超时**，可改用镜像加速器拉取后重新打 tag（实测 `docker.1ms.run` 可用，
> `daocloud` / `dockerproxy.net` 对该镜像返回 403 / TLS 超时）：
> ```shell
> docker pull docker.1ms.run/ricwang/docker-wechat:latest
> docker tag  docker.1ms.run/ricwang/docker-wechat:latest ricwang/docker-wechat:latest
> ```
> 拉取完成后再执行上面的 `docker-compose up`。

#### 二、访问

- **浏览器（推荐）**：[`http://127.0.0.1:5800`](http://127.0.0.1:5800)
- **VNC 客户端**：连接 `127.0.0.1:5900`（未设置 `VNC_PASSWORD` 时密码留空）

打开后看到微信登录界面，用手机微信扫码登录即可。

> ⚠️ **浏览器打不开 / 一直转圈的排查**：服务本身正常（`curl http://127.0.0.1:5800` 能返回 200 即证明），
> 通常是**浏览器侧**问题：
> 1. 容器没起来时访问过该地址，浏览器缓存了「失败」状态 → 按 **`Ctrl+Shift+R`** 硬刷新，或开**无痕窗口**。
> 2. **代理 / VPN**（Clash TUN、系统代理等）劫持了 `127.0.0.1` 流量 → 临时关闭代理，或把 `127.0.0.1`、`localhost` 加入直连白名单。
> 3. 换个浏览器（Edge / Firefox）试试。

#### 三、数据持久化

登录态、聊天文件、下载内容均挂载到本目录，**重建容器不丢失**：

| 宿主机路径             | 容器路径               | 说明                  |
|------------------------|------------------------|-----------------------|
| `./.xwechat`           | `/root/.xwechat`       | 微信配置 / 登录态     |
| `./xwechat_files`      | `/root/xwechat_files`  | 聊天文件 / 图片 / 视频|
| `./downloads`          | `/root/downloads`      | 下载目录              |

#### 四、Windows 适配说明（与官方 docker run 示例的差异）

官方 README 给的示例面向 Linux 宿主机，**Windows 下需做如下调整**（本编排已处理）：

1. **去掉 `-v /dev/snd:/dev/snd`**：Docker Desktop（WSL2）没有 `/dev/snd` 音频设备，
   原样挂载会报错或无效。对应环境变量改为 `WEB_AUDIO=0`。
   > VNC 协议本身不传输音频，浏览器音频需 `WEB_AUDIO=1` 且依赖 Linux 音频设备，Windows 无法用。
2. **`USER_ID=0 / GROUP_ID=0`**：以 root 运行，规避 Windows bind mount 目录的属主权限问题。
3. **`privileged: true`**：GUI 容器需要特权模式，否则界面无法正常启动。
4. **`KEEP_APP_RUNNING=1`**：微信被关闭或崩溃后容器内自动重启进程（容器不会退出）。

#### 五、常用命令

```shell
# 查看日志（启动 / 扫码登录排错）
docker logs -f wechat

# 停止
docker-compose -f docker-compose-wechat.yml -p wechat down

# 重启
docker restart wechat
```

#### 六、中文输入

镜像内**默认无中文输入法**，无法直接输入中文。两种方式：

- 复制粘贴：在宿主机复制中文文本，在 Web/VNC 界面里粘贴（noVNC 左侧面板有 Clipboard）。
- 需要内置输入法可换镜像 [`xiaoheiCat/docker-wechat-sogou-pinyin`](https://github.com/xiaoheiCat/docker-wechat-sogou-pinyin)。

#### 七、可选配置（编辑 `docker-compose-wechat.yml`）

- **访问密码**：取消注释 `VNC_PASSWORD=your_password`，Web/VNC 访问需输入密码。
- **深色模式**：取消注释 `DARK_MODE=1`。
- **分辨率**：修改 `DISPLAY_WIDTH` / `DISPLAY_HEIGHT`。
- **安全连接（HTTPS/加密 VNC）**：设置 `SECURE_CONNECTION=1`，配合证书使用，详见上游 README。

#### 八、已知问题

- 同一微信账号**无法与 PC 版微信同时在线**（会互相挤下线）。
- 聊天记录目前**不支持导出**。
- 若出现频繁闪退，可尝试在微信设置里**关闭消息提示音**。
- 部分版本镜像启动时报 `APP_NAME: /etc/cont-env.d/APP_NAME: 1: Wechat: not found`，
  通常是微信安装包未就绪，可重新拉取 `latest` 镜像或指定较新的固定 tag 重试。
