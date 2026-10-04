# Safe Cache Cleaner for macOS

一个保守设计的 macOS 第三方缓存清理脚本。它只处理代码中明确列出的缓存目录，
默认删除超过 30 天的普通文件，并跳过符号链接与正在运行的相关应用。

## Safety model

- 只访问 `~/Library/Caches`。
- 启动时验证缓存根目录的真实路径。
- 只处理脚本 `TARGETS` 白名单中的目录。
- 不处理系统缓存、Codex、微信或 `~/Library/Containers`。
- 不跟随符号链接，不跨文件系统。
- 正式删除前提供 3 秒取消时间。
- 删除行为不可恢复，请先使用预览模式。

## Preview first / 先预览

```bash
chmod +x 一键安全清理缓存.command
CACHE_CLEANUP_DRY_RUN=1 COMMAND_TOOL_NO_PAUSE=1 ./一键安全清理缓存.command
```

确认预览结果后，双击脚本或运行：

```bash
./一键安全清理缓存.command
```

可调整文件年龄阈值：

```bash
CACHE_CLEANUP_DAYS=60 ./一键安全清理缓存.command
```

日志保存到 `~/Library/Logs/one-click-cache-cleanup.log`。

## License

MIT

