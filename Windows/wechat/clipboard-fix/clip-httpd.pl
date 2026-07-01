#!/usr/bin/perl
# ============================================================
# clip-httpd.pl — 容器内极简 HTTP 服务（perl，监听 127.0.0.1:19999）
#
# 功能：接收浏览器 POST 的图片(multipart)，写入容器 X11 剪贴板(image/png)，
#       供微信 Ctrl+V 粘贴。配合 nginx 反代 /clip 使用。
#
# 接口：
#   POST /clip/send    multipart/form-data, field image=<file>  → 写剪贴板
#   GET  /clip/health  → "ok"
#
# 架构要点（X11 剪贴板所有权机制）：
#   X11 的 CLIPBOARD 是「所有权」模型——剪贴板内容由「持有所有权的进程」提供，
#   该进程退出后剪贴板即失效。因此 xclip 必须由【常驻进程】持有，不能由一次性
#   脚本/docker exec 启动（进程退出→剪贴板空）。
#
#   本服务采用「主进程持有 xclip」架构：
#     - 主进程（cinit 常驻）监听 HTTP
#     - 收到图片后，主进程 kill 旧 xclip，fork 新 xclip 持有该图片
#     - xclip 作为主进程的子进程长期存活，剪贴板内容持久
#   为避免 fork-per-connection 导致 xclip 挂在临时子进程下，这里改用
#   「串行 accept + 主进程直接 fork xclip」模型（HTTP 请求量极低，无需并发）。
#
# 由 cinit 服务托管（99-clipboard.sh 用 setsid 启动），随容器常驻。
# ============================================================
use strict;
use warnings;
use IO::Socket::INET;
use POSIX qw(WNOHANG);

$ENV{DISPLAY} ||= ':0';
my $port = $ENV{CLIP_HTTPD_PORT} || 19999;

# 当前持有剪贴板的 xclip PID（全局，主进程维护）
my $clip_pid = 0;

sub log_ { print STDERR "[" . scalar(localtime) . "] @_\n"; }

# 主进程：串行处理每个连接（图片上传是低频操作，无需并发）
my $listen = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1',
    LocalPort => $port,
    Proto     => 'tcp',
    Listen    => 5,
    ReuseAddr => 1,
) or die "[clip-httpd] cannot listen on $port: $!\n";

log_("listening on 127.0.0.1:$port");

while (1) {
    my $conn = $listen->accept();
    unless ($conn) { next; }

    # 处理一个连接（串行，主进程上下文）
    eval { handle($conn); };
    if ($@) { log_("ERROR: $@"); }
    close($conn);
}

sub handle {
    my $c = shift;
    $c->autoflush(1);

    # 1. 读 headers
    my $head = '';
    my $line;
    while (defined($line = <$c>)) {
        $head .= $line;
        last if $line =~ /^\r?\n$/;
    }

    my ($method, $path) = ($head =~ /^(\S+)\s+(\S+)/);
    my $cl = ($head =~ /Content-Length:\s*(\d+)/i) ? $1 : 0;
    my $ct = '';
    $ct = $1 if ($head =~ /Content-Type:\s*([^\r\n]+)/i);

    # 2. 读 body
    my $body = '';
    if ($cl > 0) {
        my $left = $cl;
        while ($left > 0) {
            my $n = read($c, my $buf, $left < 8192 ? $left : 8192);
            last if !defined($n) || $n == 0;
            $body .= $buf;
            $left -= $n;
        }
    }

    # 3. 路由
    if ($path =~ m{^/clip/health}) {
        reply($c, 200, 'text/plain', 'ok');
        return;
    }
    if ($path !~ m{^/clip/send}) {
        reply($c, 404, 'text/plain', 'Not Found');
        return;
    }

    # 4. 解析 multipart
    my ($boundary) = ($ct =~ /boundary="?([^";\r\n]+)"?/);
    if (!$boundary) {
        reply($c, 400, 'application/json', '{"ok":false,"error":"no boundary"}');
        return;
    }
    my $img = extract_part(\$body, $boundary);
    if (!$img || length($img) < 64) {
        reply($c, 400, 'application/json', '{"ok":false,"error":"no image in body"}');
        return;
    }

    # 5. 写入剪贴板：落临时文件 → 主进程 fork xclip 持有
    #    同时存一份到 /root/downloads/（时间戳命名，持久化、可在文件管理器查看/重发）
    my $tmp = "/tmp/.clip-current.png";
    open(my $fh, '>', $tmp) or do {
        reply($c, 500, 'application/json', '{"ok":false,"error":"cannot write tmp"}');
        return;
    };
    binmode($fh);
    print $fh $img;
    close($fh);

    # 存档到 downloads（时间戳命名，同秒冲突时加序号；目录持久化映射到宿主机）
    my $archived = '';
    if (-d '/root/downloads') {
        my @t = localtime();
        my $base = sprintf("clip_%04d%02d%02d_%02d%02d%02d",
            $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
        my $dest = "/root/downloads/$base.png";
        # 同秒内多次上传：加序号防覆盖
        my $seq = 1;
        while (-e $dest) {
            $dest = "/root/downloads/${base}_${seq}.png";
            $seq++;
        }
        if (open(my $afh, '>', $dest)) {
            binmode($afh);
            print $afh $img;
            close($afh);
            $archived = $dest;
        }
    }

    my $bytes = length($img);
    if (set_clipboard($tmp)) {
        my $arch_json = $archived ? ",\"saved\":\"$archived\"" : '';
        reply($c, 200, 'application/json', "{\"ok\":true,\"bytes\":$bytes$arch_json}");
        log_("set clipboard: $bytes bytes, saved=$archived");
    } else {
        reply($c, 500, 'application/json', '{"ok":false,"error":"xclip fork failed"}');
        log_("FAILED to set clipboard");
    }
}

# 主进程：kill 旧 xclip，fork 新 xclip 持有 $file
# xclip 作为主进程的子进程长期存活，剪贴板内容持久。
sub set_clipboard {
    my ($file) = @_;

    # 杀掉旧的 xclip 持有者
    if ($clip_pid > 0 && kill(0, $clip_pid)) {
        kill('TERM', $clip_pid);
        waitpid($clip_pid, 0);
    }
    # 清理其它残留 xclip（防止冲突）
    my @old = `pgrep -f 'xclip.*clipboard.*image/png' 2>/dev/null`;
    chomp @old;
    for my $p (@old) { kill('TERM', $p) if $p =~ /^\d+$/; }

    # fork 新 xclip
    my $pid = fork();
    return 0 unless defined $pid;
    if ($pid == 0) {
        # 子进程：exec xclip（替换进程映像，长期持有剪贴板）
        open(STDOUT, '>', '/dev/null');
        open(STDERR, '>', '/dev/null');
        exec('xclip', '-selection', 'clipboard', '-t', 'image/png', '-i', $file)
            or exit 127;
    }
    # 父进程：记录新 xclip 的 PID，不 wait（让它常驻）
    $clip_pid = $pid;
    # 收割已退出的僵尸（如果有），但不动当前 $clip_pid
    $SIG{CHLD} = sub { while ((my $z = waitpid(-1, WNOHANG)) > 0) { $clip_pid = 0 if $z == $clip_pid; } };
    select(undef, undef, undef, 0.3);  # 给 xclip 一点时间初始化
    return 1;
}

# 从 multipart body 中提取第一个文件部分
sub extract_part {
    my ($bref, $boundary) = @_;
    my $delim = "--$boundary";
    my $i = index($$bref, $delim);
    return undef if $i < 0;
    $i += length($delim);
    my $j = index($$bref, "\r\n\r\n", $i);
    return undef if $j < 0;
    my $start = $j + 4;
    my $end = index($$bref, "\r\n--$boundary", $start);
    $end = length($$bref) if $end < 0;
    return undef if $end <= $start;
    return substr($$bref, $start, $end - $start);
}

sub reply {
    my ($c, $code, $ctype, $msg) = @_;
    my $len = length($msg);
    my $status = {200=>'OK',400=>'Bad Request',404=>'Not Found',500=>'Internal Server Error'}->{$code}||'OK';
    print $c "HTTP/1.1 $code $status\r\n";
    print $c "Content-Type: $ctype\r\n";
    print $c "Content-Length: $len\r\n";
    print $c "Access-Control-Allow-Origin: *\r\n";
    print $c "Connection: close\r\n\r\n";
    print $c $msg;
}
