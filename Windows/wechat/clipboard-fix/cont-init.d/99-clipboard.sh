#!/bin/sh
# ============================================================
# 99-clipboard.sh — 剪贴板修复初始化脚本
#
# 功能：
#   1. 修复 dpkg statoverride 问题（jlesage 镜像已知问题）
#   2. 安装 xclip / autocutsel 及依赖（离线 deb 包）        [仅首次]
#   3. 启动 autocutsel 守护进程（双向同步 PRIMARY <-> CLIPBOARD）[每次启动]
#   4. 部署 clip-httpd（图片上传 HTTP 服务）+ nginx 反代     [每次启动]
#   5. 确保 img-to-clipboard 可执行
#
# 安装来源：clipboard-fix/ 目录挂载进容器
# 适用镜像：ricwang/docker-wechat (基于 jlesage/baseimage-gui，用 cinit 进程管理)
#
# ⚠️ cinit 只在容器启动时扫描一次 /etc/services.d，cont-init 阶段动态创建的
#    service 目录不会被自动发现。所以这里用 setsid 直接后台启动常驻进程。
# ============================================================

set -eu

# ============================================================
# 阶段 1：deb 安装（幂等，仅首次执行）
# ============================================================
if [ ! -f /tmp/.clipboard-fix-done ]; then
    echo "[clipboard-fix] 首次初始化..."

    # 1a. 修复 statoverride
    if grep -q "messagebus" /var/lib/dpkg/statoverride 2>/dev/null; then
        echo "[clipboard-fix] 修复 statoverride (移除 messagebus 条目)..."
        sed -i '/messagebus/d' /var/lib/dpkg/statoverride
    fi

    # 1b. 安装 deb 包
    DEB_DIR="/clipboard-fix/debs"
    if [ -d "$DEB_DIR" ]; then
        echo "[clipboard-fix] 安装剪贴板工具包..."
        dpkg -i \
            "$DEB_DIR/libice6.deb" \
            "$DEB_DIR/libsm6.deb" \
            "$DEB_DIR/libxt6.deb" \
            "$DEB_DIR/libxmu6.deb" \
            "$DEB_DIR/libxpm4.deb" \
            "$DEB_DIR/libxaw7.deb" \
            "$DEB_DIR/xclip.deb" \
            "$DEB_DIR/autocutsel.deb" \
            2>&1 | grep -E "Setting up|Unpacking|error" || true
        dpkg --force-depends --configure libxaw7 autocutsel 2>/dev/null || true
        echo "[clipboard-fix] 工具安装完成。"
    else
        echo "[clipboard-fix] 警告: $DEB_DIR 目录不存在，跳过安装。"
    fi

    touch /tmp/.clipboard-fix-done
fi

# ============================================================
# 阶段 2：部署常驻服务（每次容器启动都执行）
# ============================================================

# 2a. autocutsel 守护进程：双向同步 PRIMARY <-> CLIPBOARD（文本剪贴板）
if ! pgrep -x autocutsel >/dev/null 2>&1; then
    echo "[clipboard-fix] 启动 autocutsel..."
    setsid sh -c '
        export DISPLAY="${DISPLAY:-:0}"
        for i in $(seq 1 60); do
            [ -S "/tmp/.X11-unix/X${DISPLAY#*:}" ] && break
            sleep 1
        done
        while true; do
            autocutsel >/dev/null 2>&1 &
            P1=$!
            autocutsel -selection PRIMARY >/dev/null 2>&1 &
            P2=$!
            wait $P1 $P2 2>/dev/null
            sleep 2
        done
    ' >/dev/null 2>&1 &
fi

# 2b. clip-httpd：图片上传 HTTP 服务（perl，监听 127.0.0.1:19999）
#     部署脚本 + 网页 + nginx 反代，随容器常驻，浏览器访问 /clip/ 即用。
if ! pgrep -f clip-httpd.pl >/dev/null 2>&1; then
    echo "[clipboard-fix] 部署 clip-httpd..."

    # 脚本已通过 bind mount 在 /clipboard-fix/clip-httpd.pl
    chmod +x /clipboard-fix/clip-httpd.pl 2>/dev/null || true

    # 启动 perl HTTP 服务（respawn 循环，输出到日志文件便于排查）
    setsid sh -c '
        while true; do
            perl /clipboard-fix/clip-httpd.pl
            sleep 2
        done
    ' >/tmp/clip-httpd.log 2>&1 &

    # 注入 nginx 反代：/clip/ → clip-httpd
    NGINX_CONF="/opt/base/etc/nginx/default_site.conf"
    if [ -f "$NGINX_CONF" ] && ! grep -q "clip-httpd" "$NGINX_CONF" 2>/dev/null; then
        # 在 server 块内加 location（插入到 root 指令后）
        sed -i '/root \/opt\/noVNC;/a\
\
    # clip-httpd reverse proxy (image paste bridge)\
    location = /clip/send {\
        proxy_pass http://127.0.0.1:19999/clip/send;\
        proxy_set_header Content-Type $content_type;\
        client_max_body_size 32m;\
    }\
    location /clip/ {\
        alias /clipboard-fix/clip-web/;\
        index index.html;\
    }' "$NGINX_CONF"
        echo "[clipboard-fix] nginx 反代已注入 /clip/。"
        # reload nginx
        nginx -s reload 2>/dev/null || kill -HUP $(cat /var/run/nginx.pid 2>/dev/null) 2>/dev/null || true
    fi
fi

# 2c. 确保 img-to-clipboard 可执行（Windows bind mount 可能丢失执行位）
if [ -f /usr/local/bin/img-to-clipboard ]; then
    chmod +x /usr/local/bin/img-to-clipboard 2>/dev/null || true
fi

echo "[clipboard-fix] 初始化完成。"
