---

# 📡 VRChat Monitor

一款基于 Flutter 开发的 VRChat 好友监控应用，可实时查看好友的在线状态和所在位置。

---

## ✨ 功能特性

* 🔐 **VRChat 登录** - 支持用户名密码登录，可选记住密码功能，支持 2FA/OTP 双重验证
* 👥 **好友状态监控** - 实时显示所有好友的在线状态（在线/忙碌/请勿打扰/离线等）
* 📍 **位置追踪** - 显示好友当前所在的房间信息，包括房间类型（公开/好友+/邀请+ 等）
* 🔄 **WebSocket 实时同步** - 通过 VRChat WebSocket API 实时接收好友状态变化
* 🖼 **头像缓存** - 自动缓存好友头像图片，减少网络请求
* 🌙 **深色模式** - 支持系统级深色模式切换
* 🙋 **个人信息页** - 查看当前登录用户信息

---

## 📌 项目状态

> ⚠️ 本项目已基本完成开发

在没有新的 Issue 或严重 Bug 的情况下，项目将不会继续进行功能更新，仅在必要时进行维护。

---

## 🚀 快速开始

### 🧰 环境要求

* Flutter SDK >= 3.11.1
* Dart SDK >= 3.11.1

---

### 📦 安装步骤

1. 克隆项目

```bash
git clone https://github.com/ucrvk/vrc_monitor.git
cd vrc_monitor
```

2. 安装依赖

```bash
flutter pub get
```

3. 运行应用

```bash
flutter run
```

---

### 🛠 构建发布版本

```bash
flutter build apk --release
# 或构建 App Bundle
flutter build appbundle --release
```

---

## 🔐 权限与隐私声明

* 🌐 本应用仅使用 **网络权限**
* 🔒 不会将您的登录信息上传或存储到任何服务器
* 📱 所有认证信息仅在本地使用

👉 您的账号数据始终由您自己掌控

---

## ⚠️ 注意事项

* 👤 本应用需要有效的 VRChat 账号才能使用
* 📡 应用通过官方 VRChat API 获取数据，请遵守 VRChat 服务条款
* 🚫 请勿滥用 API，以免导致账号被限制或封禁

---

## 📜 许可证

本项目采用 **GPLv3** 许可证，详见 [LICENSE](LICENSE) 文件。

---

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

---

## 🙏 鸣谢

* 🌐 [VRChat](https://vrchat.com/) - 提供精彩的虚拟世界平台
* 🧩 [vrchat_dart](https://github.com/vrchatapi/vrchatapi-dart) - 非官方 VRChat API Dart 客户端

---

