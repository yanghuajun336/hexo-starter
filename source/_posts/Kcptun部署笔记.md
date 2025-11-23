---
title: Kcptun 部署笔记
index_img: https://www.qinzc.me/admin/editor/php/upload/62461552309694.png
---
> kcptun 极速网络隧道，让数据传输飞起来！

## 下载 kcptun

### Linux 下载
```bash
#!/usr/bin/env bash

# Detect the operating system type and architecture
OS=$(uname | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

# Map architecture to the corresponding string used in the release names
case "$ARCH" in
    x86_64 | amd64)
        ARCH="amd64"
        ;;
    i386 | i686)
        ARCH="386"
        ;;
    armv5*)
        ARCH="arm5"
        ;;
    armv6*)
        ARCH="arm6"
        ;;
    armv7*)
        ARCH="arm7"
        ;;
    aarch64 | arm64)
        ARCH="arm64"
        ;;
    mips)
        ARCH="mips"
        ;;
    mipsle)
        ARCH="mipsle"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Determine the operating system
case "$OS" in
    linux | darwin | freebsd | windows)
        OS="$OS"
        ;;
    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

# Get the latest version number and remove the 'v' prefix
LATEST_VERSION=$(curl -s https://api.github.com/repos/xtaci/kcptun/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

# Construct the download URL
DOWNLOAD_URL="https://github.com/xtaci/kcptun/releases/download/v$LATEST_VERSION/kcptun-$OS-$ARCH-$LATEST_VERSION.tar.gz"

# Display the download URL
echo "Constructed download URL: $DOWNLOAD_URL"

# Download the file
echo "Downloading kcptun $LATEST_VERSION for $OS/$ARCH..."
curl -L -O $DOWNLOAD_URL

# Extract the filename from the URL
FILENAME=$(basename $DOWNLOAD_URL)

# Check if the download was successful
if [ $? -eq 0 ]; then
    echo "Download complete: $FILENAME"
else
    echo "Download failed. Please check if the OS/ARCH combination is supported or if the URL is correct."
fi
```

### Windows 下载
在 `https://github.com/xtaci/kcptun/releases` 中找到对应版本，下载链接示例：
```
https://github.com/xtaci/kcptun/releases/download/v20250427/kcptun-windows-amd64-202x0xxx.tar.gz
```

## Linux 部署
1. 解压下载的文件。
2. 运行服务端：
   ```bash
   ./server_linux_amd64 -r 172.17.0.1:22 -l 0.0.0.0:29900 --key your_secret_key --crypt aes --mode fast2
   ```
3. 运行客户端：
   ```bash
   ./client_linux_amd64 -t 0.0.0.0:29900 -l 0.0.0.0:8388 --key your_secret_key --crypt aes --mode fast2
   ```

## Windows 部署

直接在界面上配置即可。

## Docker 部署

### 构建镜像
本次构建镜像预期通过脚本形式，自动下载 kcptun 软件，并自动生成 Dockerfile，以及运行 kcptun 应用的脚本。

1. 自动下载最新的 kcptun 软件，可以通过官方的下载脚本：
   ```bash
   # 在上面的 Linux 下载脚本中实现
   ```

2. 自动生成 kcptun 启动脚本：
    ```
    cat << EOF > startup
    #!/bin/bash

    OPTS=
    KCPTUN_PROG=

    if [ "\$KCPTUN_TYPE" = "server" ]; then
        KCPTUN_PROG=server
        [ \$KCPTUN_LISTEN ] && OPTS="\$OPTS -l \$KCPTUN_LISTEN"
        [ \$KCPTUN_TARGET ] && OPTS="\$OPTS -t \$KCPTUN_TARGET"
    else
        KCPTUN_PROG=client
        [ \$KCPTUN_LOCALADDR ] && OPTS="\$OPTS -l \$KCPTUN_LOCALADDR"
        [ \$KCPTUN_REMOTEADDR ] && OPTS="\$OPTS -r \$KCPTUN_REMOTEADDR"
    fi

    [ \$KCPTUN_MODE ] && OPTS="\$OPTS --mode \$KCPTUN_MODE"
    [ \$KCPTUN_CRYPT ] && OPTS="\$OPTS --crypt \$KCPTUN_CRYPT"

    \$KCPTUN_PROG \$OPTS &
    EOF
    ```

3. 自动生成 Dockerfile：
   ```bash
   cat << EOF > Dockerfile
    FROM alpine:3.18

    WORKDIR /usr/bin/
    COPY startup .
    COPY kcptun-\$OS-\$ARCH-\$LATEST_VERSION.tar.gz .
    RUN tar -xvf kcptun-\$OS-\$ARCH-\$LATEST_VERSION.tar.gz
    RUN mv client_* client && mv server_* server && chmod +x client && chmod +x server && chmod +x startup

    ENTRYPOINT ["./startup"]
    EOF
   ```

### 参数详解

| 参数           | 解释                                    | 属性         | 其他                                                      |
|----------------|-----------------------------------------|--------------|-----------------------------------------------------------|
| KCPTUN_TYPE    | 选择使用 kcptun 镜像的类型            | 必选参数     | server: 运行的程序为 `/usr/bin/server`<br>client: 运行的程序为 `/usr/bin/client` 默认是 client |
| KCPTUN_LISTEN  | 监听的地址和端口                       | 可选参数     | 例：`127.0.0.1:9090`<br>服务端时有效，默认为 `127.0.0.1:29900` |
| KCPTUN_TARGET   | 目标服务的地址和端口                  | 可选参数     | 例：`127.0.0.1:28800`<br>服务端时有效，默认为 `127.0.0.1:29900` |
| KCPTUN_LOCALADDR| 监听本地的地址和端口                  | 可选参数     | 例：`127.0.0.1:8000`<br>客户端时有效，默认为 `127.0.0.1:12948` |
| KCPTUN_REMOTEADDR| kcptun 服务器的地址和端口            | 可选参数     | 例：`127.0.0.1:28800`<br>客户端时有效，默认为 `127.0.0.1:29900` |
| KCPTUN_MODE    | kcptun 的工作模式                      | 可选参数     | 可选项：fast3, fast2, fast, normal, manual 默认: "fast" |
| KCPTUN_CRYPT   | kcptun 的加密方式                      | 可选参数     | 可选项：aes-128, aes-192, salsa20, blowfish, twofish, cast5, 3des, tea, xtea, xor, sm4, none, null 默认: aes |

### 运行容器
1. 运行客户端：
   ```bash
   docker run -d --name kcpclient -p 8388:8388 -e KCPTUN_TYPE="client" -e KCPTUN_LOCALADDR="0.0.0.0:8388" -e KCPTUN_REMOTEADDR="9.82.179.109:29900" kcptun-image:latest
   ```

2. 运行服务端：
   ```bash
   docker run -d --name kcpserver -p 29900:29900/udp -e KCPTUN_TYPE="server" -e KCPTUN_LISTEN="0.0.0.0:29900" -e KCPTUN_TARGET="172.17.0.1:22" kcptun-image:latest
   ```
3. docker-compose
  ```yaml
version: "3.9"

services:
  server:
    image: kcptun-image
    environment:
      KCPTUN_TYPE: "server"
      KCPTUN_LISTEN: ':50000'  # 服务器监听端口
      KCPTUN_TARGET: '172.17.0.1:22'  # 目标地址
      KCPTUN_MODE: fast2  # 模式设置
      KCPTUN_CRYPT: aes  # 加密方式
    ports:
      - "50000:50000/udp"  # 开放 UDP 端口

  client:
    image: kcptun-image
    environment:
      KCPTUN_TYPE: "client"
      KCPTUN_LOCALADDR: ':10000'  # 本地监听端口
      KCPTUN_REMOTEADDR: '9.82.179.109:50000'  # 远程服务器地址
      KCPTUN_MODE: fast2  # 模式设置
      KCPTUN_CRYPT: aes  # 加密方式
    ports:
      - "10000:10000"  # 开放 TCP 端口
  ```
## 常见问题

### 问题 1
**描述**：当 server 配置 target 为本机（宿主机）端口时，使用 `127.0.0.1:22` 或 `0.0.0.0:22`，导致流量不能被转发到目标服务。

**分析**：在容器中，`127.0.0.1` 代表容器本身，`0.0.0.0` 代表容器内部的所有地址。

**解决方案**：对于 Docker，使用宿主机的 `docker0` 网卡地址，如 `172.17.0.1`。

### 问题 2
**描述**：在 Alpine 中运行脚本时，出现 `standard_init_linux.go:190: exec user process caused "no such file or directory"` 的错误。

**分析**：Alpine 中没有 `bash`。

**解决方案**：使用 `/bin/sh` 替换 `/bin/bash`。

## 附件
一键部署脚本
```bash
一键部署脚本
#!/usr/bin/env bash

set -e  # 任何命令失败时退出脚本

export http_proxy="http://ywx1207759:joee_yang333@proxy.huawei.com:8080/"
export https_proxy="http://ywx1207759:joee_yang333@proxy.huawei.com:8080/"
# 函数：输出日志
log() {
    echo "[INFO] $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# 函数：下载文件
download_file() {
    local url=$1
    local timeout=$2
    local filename=$(basename "$url")

    log "Downloading $filename with a timeout of $timeout seconds..."
    if ! curl -k -L --max-time "$timeout" -O "$url"; then
        echo "[ERROR] Download failed or timed out for $url"
        exit 1
    fi
    log "Download complete: $filename"
}

# 函数：获取最新版本
get_latest_version() {
    local version=$(curl -sk https://api.github.com/repos/xtaci/kcptun/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    echo "$version"
}

# 函数：构建下载链接
build_download_url() {
    local os=$1
    local arch=$2
    local version=$3
    echo "https://github.com/xtaci/kcptun/releases/download/v$version/kcptun-$os-$arch-$version.tar.gz"
}

# 函数：生成启动脚本
generate_startup_script() {
    cat << EOF > startup
#!/bin/sh -x

echo "INTO: startup for kcptun "

env

OPTS=
KCPTUN_PROG=

if [ "\$KCPTUN_TYPE" = "server" ]; then
    KCPTUN_PROG=server
    [ \$KCPTUN_LISTEN ] && OPTS="\$OPTS -l \$KCPTUN_LISTEN"
    [ \$KCPTUN_TARGET ] && OPTS="\$OPTS -t \$KCPTUN_TARGET"
else
    KCPTUN_PROG=client
    [ \$KCPTUN_LOCALADDR ] && OPTS="\$OPTS -l \$KCPTUN_LOCALADDR"
    [ \$KCPTUN_REMOTEADDR ] && OPTS="\$OPTS -r \$KCPTUN_REMOTEADDR"
fi

[ \$KCPTUN_MODE ] && OPTS="\$OPTS --mode \$KCPTUN_MODE"
[ \$KCPTUN_CRYPT ] && OPTS="\$OPTS --crypt \$KCPTUN_CRYPT"

\$KCPTUN_PROG \$OPTS

#echo "kcptun(pid: $!) runing with: $KCPTUN_PROG $OPTS"
EOF
    chmod +x startup
    log "Startup script generated."
}

# 函数：生成 Dockerfile
generate_dockerfile() {
cat << EOF > Dockerfile
FROM alpine:3.18

ARG OS
ARG ARCH
ARG LATEST_VERSION

WORKDIR /root
COPY startup /bin/startup
COPY kcptun-\$OS-\$ARCH-\$LATEST_VERSION.tar.gz .
RUN tar -xvf kcptun-\$OS-\$ARCH-\$LATEST_VERSION.tar.gz \
    && mv client_* /bin/client \
    && mv server_* /bin/server \
    && chmod +x /bin/client /bin/server /bin/startup

ENTRYPOINT ["startup"]
EOF
    log "Dockerfile generated."
}

# 主程序
main() {
    log "Detecting operating system and architecture..."
    OS=$(uname | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64 | amd64) ARCH="amd64";;
        i386 | i686) ARCH="386";;
        armv5*) ARCH="arm5";;
        armv6*) ARCH="arm6";;
        armv7*) ARCH="arm7";;
        aarch64 | arm64) ARCH="arm64";;
        mips) ARCH="mips";;
        mipsle) ARCH="mipsle";;
        *) echo "[ERROR] Unsupported architecture: $ARCH"; exit 1;;
    esac

    case "$OS" in
        linux | darwin | freebsd | windows) ;;
        *) echo "[ERROR] Unsupported OS: $OS"; exit 1;;
    esac

    LATEST_VERSION=$(get_latest_version)
    DOWNLOAD_URL=$(build_download_url "$OS" "$ARCH" "$LATEST_VERSION")

    log "Constructed download URL: $DOWNLOAD_URL"

    # 设置超时时间（例如60秒）
    local timeout=60
    download_file "$DOWNLOAD_URL" "$timeout"

    log "Generating startup script..."
    generate_startup_script

    log "Generating Dockerfile..."
    generate_dockerfile

    log "All tasks completed successfully."

    # 构建 Docker 镜像时传递参数
    docker build --build-arg OS="$OS" --build-arg ARCH="$ARCH" --build-arg LATEST_VERSION="$LATEST_VERSION" -t kcptun-image .
}

# 执行主程序
main
```




