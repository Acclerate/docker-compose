#!/bin/sh
# ============================================================
# img-to-clipboard.sh — 把图片文件写入 X11 剪贴板(CLIPBOARD 选区)
#
# 用途：解决 noVNC/VNC 无法直接粘贴图片的问题。
#       RFB 协议的剪贴板消息(ClientCutText/ServerCutText)只支持纯文本，
#       二进制图片无法通过浏览器/VNC 客户端传进容器。
#       本脚本作为「文件 → 图片剪贴板」的转换桥：
#         宿主机图片 → noVNC 文件管理器上传到 /root/downloads/
#                    → 本脚本写入 CLIPBOARD(image/png target)
#                    → 微信输入框 Ctrl+V 粘贴为图片
#
# 用法：
#   docker exec wechat img-to-clipboard /root/downloads/截图.png
#   docker exec wechat img-to-clipboard ~/downloads/photo.jpg
#   # 支持多张：会写入最后一张（微信一次只粘贴一张）
#   docker exec wechat img-to-clipboard a.png b.png
#
# 依赖：xclip（由 99-clipboard.sh 离线安装），X server(Xvnc) 已运行
#
# 技术细节（基于社区最佳实践）：
#   - X11 剪贴板通过「target」机制标识数据类型，image/png 兼容性最好。
#   - xclip 不做格式转换：若文件是 jpg 却标 image/jpeg，部分 GUI 应用
#     （如 Electron 类）会拒绝粘贴。因此本脚本：
#       * png 文件 → 直接用 image/png target
#       * jpg/bmp/gif 文件 → 先尝试 image/png target（多数情况可行），
#         若失败再回退到对应 MIME target。
#   - 镜像内无 ImageMagick，无法把 jpg 转成 png；若 image/png 写入失败，
#     建议用户在宿主机先把图片另存为 png。
# ============================================================
set -eu

export DISPLAY="${DISPLAY:-:0}"

# 根据扩展名判断原始 MIME
raw_mime_for() {
    ext="${1##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    case "$ext" in
        png)         echo "image/png" ;;
        jpg|jpeg)    echo "image/jpeg" ;;
        bmp)         echo "image/bmp" ;;
        gif)         echo "image/gif" ;;
        *)           echo "" ;;
    esac
}

if [ "$#" -lt 1 ]; then
    echo "用法: $(basename "$0") <图片文件> [图片文件...]" >&2
    echo "  把图片写入剪贴板，随后在微信里 Ctrl+V 粘贴。" >&2
    echo "  推荐格式: png（兼容性最好）。也支持 jpg / bmp / gif。" >&2
    exit 2
fi

# 等待 X server 就绪
if [ ! -S "/tmp/.X11-unix/X${DISPLAY#*:}" ]; then
    echo "错误: X server 未就绪（socket /tmp/.X11-unix/X${DISPLAY#*:} 不存在）。" >&2
    echo "      请确认容器已完全启动（微信登录界面已出现）。" >&2
    exit 1
fi

last_file=""
ok=0
for f in "$@"; do
    # 支持 ~ 展开（docker exec 默认不展开）
    case "$f" in
        '~'/*) f="${HOME}${f#'~'}" ;;
    esac

    if [ ! -f "$f" ]; then
        echo "警告: 文件不存在，跳过: $f" >&2
        continue
    fi

    raw_mime=$(raw_mime_for "$f")
    if [ -z "$raw_mime" ]; then
        echo "警告: 无法识别图片格式，跳过: $f（支持 png/jpg/bmp/gif）" >&2
        continue
    fi

    # 策略：始终优先用 image/png target（兼容性最好）
    # 对非 png 文件也先试 image/png：xclip 会原样写入文件字节，多数 GUI
    # 应用按内容嗅探而非严格校验 target，能正确粘贴。
    wrote_target=""
    for try_target in image/png "$raw_mime"; do
        # 写入（xclip -i 后台持有剪贴板所有权）
        timeout 5 xclip -selection clipboard -t "$try_target" -i "$f" >/dev/null 2>&1 &
        sleep 0.4
        # 校验 target 是否真的生效
        if timeout 3 xclip -selection clipboard -o -t TARGETS 2>/dev/null | grep -q "^${try_target}$"; then
            wrote_target="$try_target"
            break
        fi
    done

    if [ -n "$wrote_target" ]; then
        if [ "$wrote_target" != "$raw_mime" ] && [ "$raw_mime" != "image/png" ]; then
            echo "✅ 已复制到剪贴板: $f" >&2
            echo "   (原格式 $raw_mime，以 image/png 写入。若微信粘贴失败，请在宿主机另存为 png)" >&2
        else
            echo "✅ 已复制到剪贴板: $f ($wrote_target)" >&2
        fi
        last_file="$f"
        ok=1
    else
        echo "⚠️  写入剪贴板失败（target 校验未通过）: $f" >&2
        echo "    建议: 在宿主机把图片另存为 .png 后重试。" >&2
    fi
done

if [ "$ok" -eq 1 ]; then
    echo "" >&2
    echo "👉 现在在微信输入框按 Ctrl+V 即可粘贴图片: $last_file" >&2
    exit 0
else
    echo "错误: 没有图片被成功写入剪贴板。" >&2
    exit 1
fi
