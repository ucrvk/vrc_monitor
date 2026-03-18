# VRChat Monitor

一款基于 Flutter 开发的 VRChat 好友监控应用，可实时查看好友的在线状态和所在位置。

## 功能特性

- **VRChat 登录** - 支持用户名密码登录，可选记住密码功能，支持 2FA/OTP 双重验证
- **好友状态监控** - 实时显示所有好友的在线状态（在线/忙碌/请勿打扰/离线等）
- **位置追踪** - 显示好友当前所在的房间信息，包括房间类型（公开/好友+/邀请+ 等）
- **WebSocket 实时同步** - 通过 VRChat WebSocket API 实时接收好友状态变化
- **头像缓存** - 自动缓存好友头像图片，减少网络请求
- **多端支持** - 可区分好友是在游戏客户端还是网页/其他端登录
- **深色模式** - 支持系统级深色模式切换
- **个人信息页** - 查看当前登录用户信息

## 快速开始

### 环境要求

- Flutter SDK >= 3.11.1
- Dart SDK >= 3.11.1
- Android / iOS / Web 设备或模拟器

### 安装步骤

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

### 构建发布版本

```bash
flutter build apk --release
# 或构建 App Bundle
flutter build appbundle --release
```


## 使用说明

1. 打开应用，输入您的 VRChat 用户名和密码
2. 如需记住密码，勾选"记住密码"选项
3. 点击"登录"按钮
4. 如需 OTP 验证，输入您的认证器生成的验证码
5. 登录成功后，可在"好友位置"页面查看所有好友的状态
6. 点击底部导航栏"我"可查看个人信息和设置

## 注意事项

- 本应用需要有效的 VRChat 账号才能使用
- 应用通过官方 VRChat API 获取数据，请遵守 VRChat 服务条款
- 请勿滥用 API 导致账号被封禁


## 许可证

本项目采用 GPVv3 许可证，详见 [LICENSE](LICENSE) 文件。

## 贡献

欢迎提交 Issue 和 Pull Request！

项目地址：https://github.com/ucrvk/vrc_monitor

## 鸣谢

- [VRChat](https://vrchat.com/) - 提供精彩的虚拟世界平台
- [vrchat_dart](https://github.com/ucrvk/vrchat_dart) - 非官方 VRChat API Dart 客户端