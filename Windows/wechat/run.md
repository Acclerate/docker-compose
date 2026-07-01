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

#### 六.五、剪贴板同步（已内置修复）

> noVNC/VNC 与容器内微信之间的**复制粘贴**已通过 `clipboard-fix/` 模块修复，无需额外操作。

**背景**：镜像基于 jlesage/baseimage-gui，X11 有 PRIMARY 与 CLIPBOARD 两个选区且默认互不相通，
导致浏览器/VNC 客户端复制的内容粘贴不进微信（反之亦然）。

**修复机制**（`clipboard-fix/`）：
1. `cont-init.d/99-clipboard.sh`：容器启动时离线安装 `xclip` + `autocutsel` 及依赖，
   并修复 jlesage 镜像的 `statoverride` (messagebus) 已知问题；幂等（`/tmp/.clipboard-fix-done` 哨兵，重启不重装）。
2. `XVNC_SERVER_CUSTOM_PARAMS=-SendPrimary on -SetPrimary on`：让 Xvnc 同步 PRIMARY 选区（变量已被上游 `xvnc/params` 脚本支持）。
3. 守护进程：脚本用 `setsid` 后台启动两个 `autocutsel` 实例，双向同步 PRIMARY ↔ CLIPBOARD，
   并带 `while` 循环实现崩溃自动重启。
   > ⚠️ 本镜像用 **cinit**（jlesage 的 C 语言 init，非 s6）做进程管理，cinit 只在容器启动时
   > 扫描一次 `/etc/services.d/`，cont-init 阶段动态创建的 service 目录不会被自动发现，
   > 因此不能走 s6 service 注册，而是在 cont-init 脚本里直接 `setsid` 启动常驻进程。
   就绪检测用 `/tmp/.X11-unix/X0` socket 文件（不依赖镜像内未安装的 `xdpyinfo`）。

**使用**：
- noVNC：点击左侧面板剪贴板图标，在文本框复制/粘贴。
- VNC 客户端：确保客户端启用了「剪贴板同步」选项。

**离线 deb 重新获取**（镜像升级到 Ubuntu 24.04 时，包名 `libxt6` → `libxt6t64`，需重新制作）：
```shell
# 在可联网的 Ubuntu 22.04 环境（或直接用该镜像容器）下载
docker run --rm --entrypoint sh ricwang/docker-wechat:latest -c '
  apt-get update -qq && apt-get download autocutsel xclip \
  libice6 libsm6 libxt6 libxmu6 libxpm4 libxaw7'
# 把下载的 .deb 放到 clipboard-fix/debs/ 替换旧文件
```

#### 六.六、图片粘贴

> ⚠️ **noVNC/VNC 协议的剪贴板只支持纯文本，无法直接粘贴图片**（RFB 协议固有限制，
> 非配置问题）。已通过「容器内置网页桥」解决：网页接收图片 → 写入容器 X11 的
> CLIPBOARD 选区（image/png target）→ 微信读取后 `Ctrl+V` 粘贴。

##### 方式一：网页桥（推荐，纯鼠标操作，容器自带）

容器启动后自带一个图片粘贴网页（`clip-httpd` + nginx 反代），**跟 noVNC 同端口同域名**，
无需手动启动任何服务。

**访问**：浏览器打开 [`http://127.0.0.1:5800/clip/`](http://127.0.0.1:5800/clip/)
（注意是 5800 端口下的 `/clip/` 路径，和微信 noVNC 同一个地址）。

**使用**：
1. `Win+Shift+S` 截图（图片进 Windows 剪贴板）
2. 网页上点 **「发送系统剪贴板里的图片」** 按钮（或把图片文件拖进方框）
3. 切到微信输入框，按 `Ctrl+V` 发送

> **原理**：网页 POST 图片 → 容器内 nginx 反代到 `clip-httpd`（perl HTTP 服务）→
> 调用 `img-to-clipboard` 写入 X11 剪贴板。全程在容器内完成，**随容器常驻**，
> 重启容器自动恢复，无需手动启动。
>
> **剪贴板权限**：点按钮时 Chrome/Edge 会弹窗问「允许查看剪贴板？」，点允许即可。
> 不想点权限就用**拖拽**：把图片文件拖到网页方框，完全不需要剪贴板权限。

##### 方式二：手动命令（无需网页）

```powershell
# 1. 把图片放进容器
docker cp 你的图片.png wechat:/root/downloads/
# 2. 写入容器剪贴板（容器内路径）
docker exec wechat img-to-clipboard /root/downloads/你的图片.png
# 3. 微信输入框 Ctrl+V
```

##### 排查

- **网页打不开 `/clip/`**：容器没启动完整，等 30s 后重试；`docker logs wechat` 看初始化日志。
- **点按钮报「请求失败」**：`clip-httpd` 没起来，`docker exec wechat sh -c "pgrep -f clip-httpd.pl"`；
  日志在容器内 `/tmp/clip-httpd.log`。
- **格式建议**：优先 **PNG**（`img-to-clipboard` 始终用 image/png target，兼容性最好）。
  镜像内无 ImageMagick，无法转格式，jpg 粘不进就另存为 png。
- **发文字**：文字用 noVNC 左侧剪贴板面板（已通过 autocutsel 双向同步）。

#### 七、可选配置（编辑 `docker-compose-wechat.yml`）

- **访问密码**：取消注释 `VNC_PASSWORD=your_password`，Web/VNC 访问需输入密码。
- **深色模式**：取消注释 `DARK_MODE=1`。
- **分辨率**：修改 `DISPLAY_WIDTH` / `DISPLAY_HEIGHT`。
- **安全连接（HTTPS/加密 VNC）**：设置 `SECURE_CONNECTION=1`，配合证书使用，详见上游 README。

#### 七.五、时间同步（让容器时间始终对齐网络）

> Docker 容器与宿主机**共享内核时钟**，无法独立同步网络时间。
> 因此让容器时间正确 = 让宿主机 Windows 时间正确。

**一次性配置**（需管理员权限的 PowerShell）：
```powershell
powershell -ExecutionPolicy Bypass -File setup-ntp.ps1
```

脚本会：① 设 `w32time` 服务为自动启动；② NTP 源换成阿里云（`ntp.aliyun.com` / `ntp1.aliyun.com`）+ 腾讯云兜底；③ 立即同步一次。

配置后**开机自动同步**，容器时间自动跟随，无需再管。

**手动验证**：
```powershell
w32tm /query /status       # 查看同步状态，源应是 ntp.aliyun.com
docker exec wechat date    # 容器时间应与宿主机一致
```

> 也可手动立即同步：`w32tm /resync /force`（需管理员）

#### 八、已知问题

- 同一微信账号**无法与 PC 版微信同时在线**（会互相挤下线）。
- 聊天记录目前**不支持导出**。
- 若出现频繁闪退，可尝试在微信设置里**关闭消息提示音**。
- 部分版本镜像启动时报 `APP_NAME: /etc/cont-env.d/APP_NAME: 1: Wechat: not found`，
  通常是微信安装包未就绪，可重新拉取 `latest` 镜像或指定较新的固定 tag 重试。
