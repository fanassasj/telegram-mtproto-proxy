# GitHub 上传完整教程

## 第一步：创建 GitHub 仓库

### 1. 登录 GitHub
访问：https://github.com/login

### 2. 创建新仓库
访问：https://github.com/new

或点击右上角 `+` → `New repository`

### 3. 填写仓库信息

```
Repository name: telegram-mtproto-proxy
Description: 简单、安全、功能完整的 Telegram MTProto 代理服务器

Public (选择公开)

❌ 不要勾选 "Add a README file"
❌ 不要勾选 "Add .gitignore"  
❌ 不要勾选 "Choose a license"
```

### 4. 点击 "Create repository"

## 第二步：推送代码

### 1. 在服务器上执行

```bash
# 进入项目目录
cd /root/telegram-mtproto-proxy

# 添加远程仓库
git remote add origin https://github.com/fanassasj/telegram-mtproto-proxy.git

# 重命名分支为 main
git branch -M main

# 推送代码
git push -u origin main
```

### 2. 输入 GitHub 凭证

**如果提示输入用户名和密码：**

- Username: `fanassasj`
- Password: 使用 **Personal Access Token**（不是密码）

**如何获取 Token：**
1. 访问：https://github.com/settings/tokens
2. 点击 `Generate new token` → `Generate new token (classic)`
3. 勾选 `repo` 权限
4. 点击 `Generate token`
5. 复制 Token（只显示一次）

### 3. 验证推送成功

访问：https://github.com/fanassasj/telegram-mtproto-proxy

应该能看到所有文件！

## 第三步：完善仓库

### 1. 添加 Topics

在仓库页面点击 ⚙️ (Settings) 旁边的齿轮图标

添加 Topics:
```
telegram
proxy
mtproto
docker
bash
vpn
privacy
security
```

### 2. 编辑仓库描述

点击 `About` 旁边的齿轮图标

```
Description: 简单、安全、功能完整的 Telegram MTProto 代理服务器 | 一键部署 | 完整监控 | 支持伪装

Website: (留空或填写文档链接)

Topics: (已在上面添加)

✅ Releases
✅ Packages
✅ Deployments
```

### 3. 启用功能

在仓库 Settings 中：
- ✅ Issues
- ✅ Discussions (可选)
- ✅ Projects (可选)
- ✅ Wiki (可选)

## 第四步：验证项目

### 1. 测试克隆

在另一台机器上测试：
```bash
git clone https://github.com/fanassasj/telegram-mtproto-proxy.git
cd telegram-mtproto-proxy
ls -la
```

### 2. 检查文件

确认以下文件存在：
- ✅ README.md
- ✅ LICENSE
- ✅ proxy.sh
- ✅ start.sh
- ✅ 其他脚本

### 3. 检查 .gitignore

确认以下文件**不存在**：
- ❌ .env
- ❌ docker-compose.yml
- ❌ config/

## 第五步：分享项目（可选）

### 1. 生成项目链接

```
仓库地址: https://github.com/fanassasj/telegram-mtproto-proxy
克隆命令: git clone https://github.com/fanassasj/telegram-mtproto-proxy.git
```

### 2. 分享到社区

- Telegram 群组
- Reddit r/Telegram
- V2EX
- 博客文章

### 3. 添加 Star

给自己的项目点个 Star ⭐

## 常见问题

### Q1: 推送时提示 "Permission denied"
**A:** 使用 Personal Access Token 而不是密码

### Q2: 推送时提示 "remote: Repository not found"
**A:** 检查仓库名是否正确，确认已创建仓库

### Q3: 如何更新代码？
**A:** 
```bash
cd /root/telegram-mtproto-proxy
git add .
git commit -m "Update: 描述更新内容"
git push
```

### Q4: 如何删除远程仓库？
**A:** 在 GitHub 仓库 Settings → Danger Zone → Delete this repository

### Q5: 推送后发现错误怎么办？
**A:** 
```bash
# 修改文件后
git add .
git commit -m "Fix: 修复问题"
git push
```

## 完成检查清单

- [ ] GitHub 仓库已创建
- [ ] 代码已推送成功
- [ ] README.md 显示正常
- [ ] Topics 已添加
- [ ] 仓库描述已设置
- [ ] Issues 已启用
- [ ] 测试克隆成功
- [ ] .gitignore 工作正常

## 下一步

1. ⭐ 给项目点 Star
2. 📝 写一篇使用教程
3. 🔔 关注 Issues 和反馈
4. 🚀 发布 v1.0.0 Release（稳定后）

---

完成！你的项目已经在 GitHub 上了 🎉

仓库地址：https://github.com/fanassasj/telegram-mtproto-proxy
