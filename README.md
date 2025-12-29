# Raspberry Pi Documentation Server

本项目由AI生成

## 项目简介

这是一个用于在本地服务器上部署树莓派官方文档的项目。它提供了一个完整的DEB包，可以轻松安装和管理树莓派文档服务器。

## 功能特性

- 从GitHub自动克隆最新的树莓派官方文档
- 提供本地HTTP服务器访问文档（端口8081）
- 自动替换外部链接为本地链接
- 支持IPv4和IPv6访问
- 提供自动更新脚本
- systemd服务管理

## 安装方法

```bash
sudo dpkg -i raspberry-pi-docs-deb-clean.deb
```

## 访问文档

安装完成后，可以通过以下地址访问文档：

- IPv4: http://[服务器IP]:8081/documentation/
- IPv6: http://[服务器IPv6]:8081/documentation/

## 更新文档

使用以下命令更新文档：

```bash
sudo /usr/share/raspberry-pi-docs/update_docs_clean.sh
```

或

```bash
sudo update_docs_clean.sh
```

## 卸载

```bash
sudo dpkg -r raspberry-pi-docs
```

## 系统要求

- Debian/Ubuntu系统
- Python 3
- Git
- Curl