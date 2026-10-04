#!/bin/zsh

# Remove old files from an explicit allowlist of third-party macOS caches.
# Set CACHE_CLEANUP_DRY_RUN=1 to preview without deleting anything.

emulate -L zsh
set -u
setopt NO_NOMATCH

readonly DAYS="${CACHE_CLEANUP_DAYS:-30}"
readonly DRY_RUN="${CACHE_CLEANUP_DRY_RUN:-0}"
readonly CACHE_ROOT="${HOME}/Library/Caches"
readonly LOG_DIR="${HOME}/Library/Logs"
readonly LOG_FILE="${LOG_DIR}/one-click-cache-cleanup.log"

if [[ ! "$DAYS" =~ '^[0-9]+$' ]] || (( DAYS < 1 )); then
  print -u2 -- "CACHE_CLEANUP_DAYS 必须是大于 0 的整数。"
  exit 1
fi

print -Pn '\e]0;一键安全清理缓存\a'
clear

print -- "========================================"
print -- "        macOS 一键安全清理缓存"
print -- "========================================"
print -- ""
print -- "将处理选定第三方缓存中超过 ${DAYS} 天的文件。"
print -- "不会处理系统缓存、Codex、微信或 Library/Containers。"
print -- "相关应用正在运行时会自动跳过。"
[[ "$DRY_RUN" == "1" ]] && print -- "当前为预览模式，不会删除任何文件。"
print -- ""

if [[ ! -d "$CACHE_ROOT" ]]; then
  print -u2 -- "未找到缓存目录：$CACHE_ROOT"
  [[ "${COMMAND_TOOL_NO_PAUSE:-0}" != "1" ]] && read -k 1 "?按任意键关闭窗口……"
  exit 1
fi

CACHE_ROOT_REAL="$(cd "$CACHE_ROOT" && pwd -P)"
if [[ "$CACHE_ROOT_REAL" != "${HOME}/Library/Caches" ]]; then
  print -u2 -- "安全检查失败，实际路径为：$CACHE_ROOT_REAL"
  [[ "${COMMAND_TOOL_NO_PAUSE:-0}" != "1" ]] && read -k 1 "?按任意键关闭窗口……"
  exit 1
fi

if [[ "$DRY_RUN" != "1" ]]; then
  print -- "3 秒后开始；如需取消，请按 Control+C。"
  trap 'print -- "\n已取消，没有继续清理。"; sleep 1; exit 130' INT
  sleep 1
  print -- "2……"
  sleep 1
  print -- "1……"
  sleep 1
  print -- ""
fi

mkdir -p "$LOG_DIR" 2>/dev/null || true
ERROR_LOG="/dev/null"
if { : >> "$LOG_FILE" } 2>/dev/null; then
  ERROR_LOG="$LOG_FILE"
  print -r -- "$(date '+%Y-%m-%d %H:%M:%S') cleanup started (dry_run=$DRY_RUN)" >> "$LOG_FILE"
fi

human_bytes() {
  awk -v bytes="$1" 'BEGIN {
    split("B KiB MiB GiB TiB", units, " ");
    i = 1;
    while (bytes >= 1024 && i < 5) { bytes /= 1024; i++ }
    printf "%.1f %s", bytes, units[i]
  }'
}

any_process_running() {
  local csv="$1"
  local process_name

  [[ -z "$csv" ]] && return 1
  for process_name in ${(s:,:)csv}; do
    if pgrep -x "$process_name" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

# Format: cache directory name|process names to avoid, separated by commas.
TARGETS=(
  'Google|Google Chrome,GoogleUpdater'
  'pip|'
  'Zotero|Zotero'
  'JetBrains|PyCharm,jetbrains-toolbox'
  'Steam|Steam,steam_osx'
  'electron|'
  'node-gyp|'
  'QGIS|QGIS'
  'com.adobe.Photoshop|Adobe Photoshop 2026'
  'Homebrew|brew'
)

integer total_files=0
integer total_bytes=0
integer cleaned_targets=0
integer skipped_targets=0
integer failed_targets=0

for entry in "${TARGETS[@]}"; do
  cache_name="${entry%%|*}"
  processes="${entry#*|}"
  target="${CACHE_ROOT_REAL}/${cache_name}"

  [[ -e "$target" ]] || continue

  if [[ -L "$target" || ! -d "$target" ]]; then
    print -- "⚠️  跳过 $cache_name：不是普通目录"
    (( skipped_targets++ ))
    continue
  fi

  case "$target" in
    "${CACHE_ROOT_REAL}"/*) ;;
    *)
      print -- "⚠️  跳过 $cache_name：路径安全检查失败"
      (( skipped_targets++ ))
      continue
      ;;
  esac

  if any_process_running "$processes"; then
    print -- "⏭️  跳过 $cache_name：相关应用正在运行"
    (( skipped_targets++ ))
    continue
  fi

  stats="$(find "$target" -xdev -type f -mtime +"$DAYS" -exec stat -f '%z' {} + 2>/dev/null | awk '{ count++; bytes += $1 } END { print count + 0, bytes + 0 }')"
  file_count="${stats%% *}"
  byte_count="${stats##* }"

  if (( file_count == 0 )); then
    print -- "✓  $cache_name：无需清理"
    continue
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    print -- "🔎 $cache_name：将删除 ${file_count} 个文件，约 $(human_bytes "$byte_count")"
    (( total_files += file_count ))
    (( total_bytes += byte_count ))
    (( cleaned_targets++ ))
    continue
  fi

  if find "$target" -xdev -type f -mtime +"$DAYS" -delete 2>>"$ERROR_LOG"; then
    find "$target" -xdev -depth -mindepth 1 -type d -empty -mtime +"$DAYS" -delete 2>>"$ERROR_LOG" || true
    print -- "🧹 $cache_name：${file_count} 个文件，约 $(human_bytes "$byte_count")"
    (( total_files += file_count ))
    (( total_bytes += byte_count ))
    (( cleaned_targets++ ))
  else
    print -- "❌ $cache_name：部分文件无法删除"
    (( failed_targets++ ))
  fi
done

print -- ""
print -- "========================================"
[[ "$DRY_RUN" == "1" ]] && print -- "预览完成" || print -- "清理完成"
print -- "已处理目录：${cleaned_targets}"
[[ "$DRY_RUN" == "1" ]] && print -- "将删除文件：${total_files}" || print -- "已删除文件：${total_files}"
print -- "预计释放空间：$(human_bytes "$total_bytes")"
print -- "跳过目录：${skipped_targets}"
(( failed_targets > 0 )) && print -- "失败目录：${failed_targets}（详情见日志）"
print -- "日志：$LOG_FILE"
print -- "========================================"
print -- ""
[[ "${COMMAND_TOOL_NO_PAUSE:-0}" != "1" ]] && read -k 1 "?按任意键关闭窗口……"
print -- ""

(( failed_targets == 0 ))

