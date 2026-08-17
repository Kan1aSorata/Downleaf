# 为 Downleaf 做贡献

感谢你愿意帮助 Downleaf 变得更好。这个项目优先保持原生、极简、文件优先和可维护性；新增功能应当服务于 Markdown 编辑、阅读或文档导航，而不是扩展成知识库或账号平台。

## 开发环境

- macOS 14 或更高版本
- Xcode 26 或兼容 Swift 6.2 的更新版本
- Git

打开 `Downleaf.xcodeproj`，选择共享的 `Downleaf` Scheme 与 `My Mac`，按 `⌘R` 即可运行。

## 提交修改

1. Fork 仓库并从 `main` 创建聚焦单一问题的分支。
2. 保持修改范围清晰，不提交构建产物、用户设置或依赖缓存。
3. 为解析、渲染和文档行为变化补充测试。
4. 在提交 Pull Request 前运行：

   ```sh
   xcodebuild -project Downleaf.xcodeproj -scheme Downleaf -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
   ```

5. 在 Pull Request 中说明问题、设计取舍、验证方式；界面修改请附截图。

## 代码与产品原则

- 优先采用 macOS 原生能力和系统交互习惯。
- 不引入账号、遥测或联网依赖，除非经过明确讨论。
- 文件写入必须可预期，不得静默改变用户路径或格式。
- 避免为了少量便利引入大型依赖。
- 用户可见文本默认使用简体中文；命名和代码注释使用清晰英文。

提交贡献即表示你同意按照仓库的 MIT License 授权该贡献。
