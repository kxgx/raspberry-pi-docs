#!/bin/bash

# 通用的树莓派文档更新脚本
# 在安装时从GitHub克隆最新文档，如果失败则使用本地文件

set -e  # 遇到错误时退出

# 定义颜色输出
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m" # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 错误处理函数
handle_error() {
    log_error "脚本执行失败，退出码: $1"
    log_info "尝试重启服务以确保服务正常运行..."
    sudo systemctl start raspberry-pi-docs.service || log_error "重启服务失败"
    exit $1
}

# 设置错误陷阱
trap 'handle_error $LINENO' ERR

log_info "正在停止文档服务器..."
if sudo systemctl is-active --quiet raspberry-pi-docs.service; then
    sudo systemctl stop raspberry-pi-docs.service || { log_error "停止服务失败"; exit 1; }
    log_info "服务已停止"
else
    log_warn "服务未运行，继续执行"
fi

# 设置文档仓库路径
DOC_REPO_DIR="/opt/raspberry-pi-documentation"

log_info "正在获取最新文档..."

# 如果文档仓库不存在，从GitHub克隆
if [ ! -d "$DOC_REPO_DIR" ]; then
    log_info "克隆文档仓库到 $DOC_REPO_DIR..."
    git clone https://github.com/raspberrypi/documentation.git "$DOC_REPO_DIR" || { 
        log_error "克隆文档仓库失败，尝试使用本地备份"
        # 如果克隆失败，使用预构建的文档
        if [ -d "/opt/raspberry-pi-docs/documentation" ]; then
            log_info "使用预构建的文档..."
            cp -r /opt/raspberry-pi-docs/documentation/* /opt/raspberry-pi-docs/
            rm -rf /opt/raspberry-pi-docs/documentation
        else
            log_error "没有可用的文档源"
            exit 1
        fi
        sudo systemctl start raspberry-pi-docs.service || { log_error "启动服务失败"; exit 1; }
        exit 0
    }
fi

# 进入文档目录
cd "$DOC_REPO_DIR" || { log_error "无法进入文档目录"; exit 1; }

log_info "拉取最新文档..."
git fetch origin || { log_error "获取远程更新失败"; exit 1; }

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/master)

if [ "$LOCAL" != "$REMOTE" ]; then
    log_info "发现新版本，正在更新..."
    git reset --hard origin/master || { log_error "重置到远程主分支失败"; exit 1; }
    
    # 尝试构建文档（如果系统有必要的工具）
    if command -v bundle >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
        log_info "构建文档..."
        make clean || log_warn "清理失败，继续构建"
        make || log_warn "构建失败，使用预构建的文档"
    fi
    
    # 更新服务目录
    log_info "更新服务目录..."
    # 检查是否有构建好的文档
    if [ -d "documentation/html" ]; then
        # 使用构建好的文档
        rm -rf /opt/raspberry-pi-docs-new/documentation
        mkdir -p /opt/raspberry-pi-docs-new/documentation
        cp -r documentation/html/* /opt/raspberry-pi-docs-new/documentation/ || { log_error "复制文档失败"; exit 1; }
    else
        # 如果没有构建好的文档，尝试使用预构建的文档
        if [ -d "/opt/raspberry-pi-docs/documentation" ]; then
            log_info "使用预构建的文档..."
            rm -rf /opt/raspberry-pi-docs-new/documentation
            mkdir -p /opt/raspberry-pi-docs-new/documentation
            cp -r /opt/raspberry-pi-docs/documentation/* /opt/raspberry-pi-docs-new/documentation/ || { log_error "复制预构建文档失败"; exit 1; }
        else
            log_error "没有可用的文档"
            sudo systemctl start raspberry-pi-docs.service || log_error "启动服务失败"
            exit 1
        fi
    fi
    
    # 备份旧文档目录并移动新目录
    rm -rf /opt/raspberry-pi-docs-old
    mv /opt/raspberry-pi-docs /opt/raspberry-pi-docs-old 2>/dev/null || true
    mv /opt/raspberry-pi-docs-new /opt/raspberry-pi-docs
    
    log_info "替换外部链接为本地链接..."
    find /opt/raspberry-pi-docs -name "*.html" -type f -exec sed -i 's|https://www.raspberrypi.com/documentation/|/documentation/|g' {} \; || log_warn "替换文档链接失败"
    find /opt/raspberry-pi-docs -name "*.html" -type f -exec sed -i 's|https://www.raspberrypi.com/|/|g' {} \; || log_warn "替换网站链接失败"
    find /opt/raspberry-pi-docs -name "*.html" -type f -exec sed -i 's|https://forums.raspberrypi.com/|/forums/|g; s|https://datasheets.raspberrypi.com/|/datasheets/|g; s|https://pip.raspberrypi.com|/pip|g; s|https://investors.raspberrypi.com/|/investors/|g; s|https://events.raspberrypi.com/|/events/|g; s|https://magazine.raspberrypi.com|/magazine/|g' {} \; || log_warn "替换其他外部链接失败"
    
    log_info "启动文档服务器..."
    sudo systemctl start raspberry-pi-docs.service || { log_error "启动服务失败"; exit 1; }
    
    # 等待服务启动
    sleep 3
    
    log_info "检查服务状态..."
    sudo systemctl status raspberry-pi-docs.service --no-pager | head -10
    
    log_info "验证文档访问..."
    if curl -s -w "%{http_code}" -o /dev/null http://localhost:8081/documentation/ | grep -q "200"; then
        log_info "文档首页正常"
    else
        log_error "文档首页访问失败"
        exit 1
    fi
    
    if curl -s -w "%{http_code}" -o /dev/null http://localhost:8081/documentation/computers/ | grep -q "200"; then
        log_info "计算机部分正常"
    else
        log_error "计算机部分访问失败"
        exit 1
    fi
    
    log_info "文档更新完成！"
    
    # 清理旧目录
    rm -rf /opt/raspberry-pi-docs-old
else
    log_info "文档已是最新版本，无需更新"
    # 重启服务以确保运行正常
    sudo systemctl start raspberry-pi-docs.service || { log_error "启动服务失败"; exit 1; }
fi

IP_ADDR=$(hostname -I | awk '{print $1}')
if [ -z "$IP_ADDR" ]; then
    IP_ADDR="localhost"
fi
log_info "服务器地址: http://$IP_ADDR:8081/documentation/"