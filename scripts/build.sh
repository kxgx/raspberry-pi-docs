#!/bin/bash

# 构建树莓派文档DEB包的脚本

set -e

echo "开始构建树莓派文档DEB包..."

# 创建构建目录
BUILD_DIR="/tmp/raspberry-pi-docs-build"
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR

# 创建DEBIAN目录结构
mkdir -p $BUILD_DIR/DEBIAN
mkdir -p $BUILD_DIR/opt
mkdir -p $BUILD_DIR/usr/local/bin
mkdir -p $BUILD_DIR/usr/share/raspberry-pi-docs

# 创建控制文件
cat > $BUILD_DIR/DEBIAN/control << 'CONTROL_EOF'
Package: raspberry-pi-docs
Version: 1.0.4-1
Section: utils
Priority: optional
Architecture: all
Depends: python3, git, curl
Maintainer: Raspberry Pi Documentation Maintainer
Description: Raspberry Pi Documentation with local server and auto-update functionality
 Complete Raspberry Pi documentation served locally with auto-update capability.
 Includes scripts to update documentation and systemd service configuration.
CONTROL_EOF

# 创建preinst脚本
cat > $BUILD_DIR/DEBIAN/preinst << 'PREINST_EOF'
#!/bin/bash
set -e

echo "Preparing to install Raspberry Pi Documentation..."

# 停止现有服务（如果存在）
systemctl stop raspberry-pi-docs.service 2>/dev/null || true

exit 0
PREINST_EOF

# 创建postinst脚本
cat > $BUILD_DIR/DEBIAN/postinst << 'POSTINST_EOF'
#!/bin/bash
set -e

echo "Configuring Raspberry Pi Documentation..."

# 设置文档仓库路径
DOC_REPO_DIR="/opt/raspberry-pi-documentation"

echo "正在获取最新文档..."

# 如果文档仓库不存在，从GitHub克隆
if [ ! -d "$DOC_REPO_DIR" ]; then
    echo "克隆文档仓库到 $DOC_REPO_DIR..."
    git clone https://github.com/raspberrypi/documentation.git "$DOC_REPO_DIR" || { 
        echo "克隆文档仓库失败，尝试使用预构建的文档..."
        # 如果克隆失败，使用预构建的文档
        if [ -d "/opt/raspberry-pi-docs/documentation" ]; then
            cp -r /opt/raspberry-pi-docs/documentation/* /opt/raspberry-pi-docs/ 2>/dev/null || true
            rm -rf /opt/raspberry-pi-docs/documentation 2>/dev/null || true
        else
            echo "错误：没有可用的文档源"
            exit 1
        fi
    }
fi

# 进入文档目录
cd "$DOC_REPO_DIR" || { echo "无法进入文档目录"; exit 1; }

# 拉取最新更新
git fetch origin || echo "获取远程更新失败，继续使用本地版本"

# 检出最新的master分支
git reset --hard origin/master || echo "重置到远程主分支失败，使用本地版本"

# 尝试构建文档（如果系统有必要的工具）
if command -v bundle >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
    echo "构建文档..."
    make clean || echo "清理失败，继续构建"
    make || echo "构建失败，使用预构建的文档"
fi

# 创建正确的目录结构以匹配Jekyll的baseurl设置
rm -rf /opt/raspberry-pi-docs-new/documentation
mkdir -p /opt/raspberry-pi-docs-new/documentation

# 尝试构建文档（如果系统有必要的工具）
if command -v bundle >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
    echo "构建文档..."
    # 清理之前的构建
    make clean 2>/dev/null || echo "清理失败，继续构建"
    # 执行构建
    if make; then
        echo "文档构建成功"
    else
        echo "构建失败，尝试使用预构建的文档"
    fi
else
    echo "系统缺少构建工具，尝试使用预构建的文档"
fi

# 检查是否有构建好的文档
if [ -d "documentation/html" ]; then
    # 使用构建好的文档
    cp -r documentation/html/* /opt/raspberry-pi-docs-new/documentation/
else
    # 如果没有构建好的文档，使用预构建的文档
    if [ -d "/opt/raspberry-pi-docs/documentation" ]; then
        echo "使用预构建的文档..."
        cp -r /opt/raspberry-pi-docs/documentation/* /opt/raspberry-pi-docs-new/documentation/ 2>/dev/null || true
    else
        echo "警告：没有可用的文档，服务将显示空目录"
    fi
fi

# 备份旧文档目录并移动新目录
rm -rf /opt/raspberry-pi-docs-old
mv /opt/raspberry-pi-docs /opt/raspberry-pi-docs-old 2>/dev/null || true
mv /opt/raspberry-pi-docs-new /opt/raspberry-pi-docs

# 创建 systemd 服务
cat > /etc/systemd/system/raspberry-pi-docs.service << 'SERVICE_EOF'
[Unit]
Description=Raspberry Pi Documentation Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/raspberry-pi-docs
ExecStart=/usr/bin/python3 -m http.server 8081 --directory /opt/raspberry-pi-docs
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# 替换文档中的外部链接
find /opt/raspberry-pi-docs -name "*.html" -type f -exec sed -i 's|https://www.raspberrypi.com/documentation/|/documentation/|g' {} \;
find /opt/raspberry-pi-docs -name "*.html" -type f -exec sed -i 's|https://www.raspberrypi.com/|/|g' {} \;
find /opt/raspberry-pi-docs -name "*.html" -type f -exec sed -i 's|https://forums.raspberrypi.com/|/forums/|g; s|https://datasheets.raspberrypi.com/|/datasheets/|g; s|https://pip.raspberrypi.com|/pip|g; s|https://investors.raspberrypi.com/|/investors/|g; s|https://events.raspberrypi.com/|/events/|g; s|https://magazine.raspberrypi.com|/magazine/|g' {} \;

# 启用并启动服务
systemctl daemon-reload
systemctl enable raspberry-pi-docs.service
systemctl start raspberry-pi-docs.service

# 获取当前服务器IP地址
IPV4_ADDR=$(hostname -I | awk '{print $1}')
if [ -z "$IPV4_ADDR" ]; then
    # 如果hostname -I不可用，尝试其他方法
    IPV4_ADDR=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit;}')
    if [ -z "$IPV4_ADDR" ]; then
        IPV4_ADDR=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | head -n1 | awk '{print $2}' | cut -d'/' -f1)
    fi
fi

if [ -z "$IPV4_ADDR" ]; then
    IPV4_ADDR="localhost"
fi

# 尝试获取IPv6地址
IPV6_ADDR=$(ip -6 addr show | grep 'inet6 ' | grep -v '::1' | grep -v 'fe80' | head -n1 | awk '{print $2}' | cut -d'/' -f1)

echo "Raspberry Pi Documentation installed and running!"
echo "Access the documentation at:"
echo "  IPv4: http://$IPV4_ADDR:8081/documentation/"
if [ -n "$IPV6_ADDR" ]; then
    echo "  IPv6: http://[$IPV6_ADDR]:8081/documentation/"
fi

exit 0
POSTINST_EOF

# 创建postrm脚本
cat > $BUILD_DIR/DEBIAN/postrm << 'POSTRM_EOF'
#!/bin/bash
set -e

case "$1" in
    remove|purge)
        # 停止并禁用服务
        systemctl stop raspberry-pi-docs.service 2>/dev/null || true
        systemctl disable raspberry-pi-docs.service 2>/dev/null || true
        
        # 删除服务文件
        rm -f /etc/systemd/system/raspberry-pi-docs.service
        
        # 重新加载systemd
        systemctl daemon-reload
        ;;
    *)
        ;;
esac

exit 0
POSTRM_EOF

# 复制更新脚本
cp ./scripts/update_docs_clean.sh $BUILD_DIR/usr/share/raspberry-pi-docs/

# 设置脚本权限
chmod +x $BUILD_DIR/DEBIAN/preinst $BUILD_DIR/DEBIAN/postinst $BUILD_DIR/DEBIAN/postrm
chmod +x $BUILD_DIR/usr/share/raspberry-pi-docs/update_docs_clean.sh

# 创建一个示例文档目录结构（模拟预构建的文档）
mkdir -p $BUILD_DIR/opt/raspberry-pi-docs/documentation

# 构建DEB包
cd /tmp
dpkg-deb --build raspberry-pi-docs-build

# 移动DEB包到项目根目录
mkdir -p ./deb-pkg
mv /tmp/raspberry-pi-docs-build.deb ./deb-pkg/raspberry-pi-docs-latest.deb

# 确保在GitHub Actions环境中也能正确复制文件
mkdir -p /home/runner/work/raspberry-pi-docs/raspberry-pi-docs/deb-pkg 2>/dev/null || true
cp ./deb-pkg/raspberry-pi-docs-latest.deb /home/runner/work/raspberry-pi-docs/raspberry-pi-docs/deb-pkg/raspberry-pi-docs-latest.deb 2>/dev/null || true

echo "构建完成！DEB包已保存到 ./deb-pkg/raspberry-pi-docs-latest.deb"
