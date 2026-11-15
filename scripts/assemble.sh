#!/usr/bin/env bash
# scripts/assemble.sh —— 按 manifest.json 组装交付物（Linux / macOS）。
# 每次运行清空 .work/ 与 dist/，保证可重复执行。
#
# 用法：
#   GODOT_BIN=/path/to/godot ./scripts/assemble.sh
#   SKIP_EXPORT=1 ./scripts/assemble.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${1:-$ROOT/manifest.json}"
OUT="${2:-$ROOT/dist}"
WORK="${3:-$ROOT/.work}"
GODOT="${GODOT_BIN:-}"
SKIP_EXPORT="${SKIP_EXPORT:-0}"

[ -f "$MANIFEST" ] || { echo "找不到 manifest: $MANIFEST" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "需要 python3 解析 manifest" >&2; exit 1; }

clone_checkout() {
    local repo="$1" ref="$2" dest="$3"
    rm -rf "$dest"
    if git clone --quiet --depth 1 --branch "$ref" "$repo" "$dest" 2>/dev/null; then
        return 0
    fi
    rm -rf "$dest"
    echo "  ref 不是分支/tag，回退到 commit 检出: $ref"
    git clone --quiet --depth 1 "$repo" "$dest"
    git -C "$dest" fetch --quiet --depth 1 origin "$ref"
    git -C "$dest" checkout --quiet --detach FETCH_HEAD
}

copy_plugin() {
    local src="$1" dest="$2" id="$3"
    [ -f "$src/plugin.json" ] || { echo "插件缺少 plugin.json: $id（$src）" >&2; exit 1; }
    mkdir -p "$dest"
    cp -R "$src/." "$dest/"
    find "$dest" -type d -name .godot -prune -exec rm -rf {} +
}

echo "清理输出与工作目录 ..."
rm -rf "$OUT" "$WORK"
mkdir -p "$OUT" "$WORK"

mapfile -t meta < <(python3 - "$MANIFEST" <<'PY'
import json, sys
m = json.load(open(sys.argv[1], encoding='utf-8'))
print(m['core']['repo'])
print(m['core']['ref'])
print(m['core'].get('subdir', '.'))
for p in m['plugins']:
    if p.get('enabled', True):
        print('\t'.join([p['id'], p['repo'], p['ref'], p['subdir']]))
PY
)
CORE_REPO="${meta[0]}"
CORE_REF="${meta[1]}"
CORE_SUBDIR="${meta[2]}"

echo "检出 core: $CORE_REPO@$CORE_REF"
clone_checkout "$CORE_REPO" "$CORE_REF" "$WORK/core"
CORE_DIR="$WORK/core"
[ "$CORE_SUBDIR" = "." ] || CORE_DIR="$WORK/core/$CORE_SUBDIR"

mkdir -p "$OUT/mods"
enabled=0
for line in "${meta[@]:3}"; do
    IFS=$'\t' read -r id repo ref subdir <<< "$line"
    if [ "$repo" = "$CORE_REPO" ] && [ "$ref" = "$CORE_REF" ]; then
        src="$WORK/core/$subdir"
    else
        echo "检出插件 $id: $repo@$ref"
        clone_checkout "$repo" "$ref" "$WORK/plugins/$id"
        src="$WORK/plugins/$id/$subdir"
    fi
    copy_plugin "$src" "$OUT/mods/$id" "$id"
    echo "已收集插件: $id"
    enabled=$((enabled + 1))
done

if [ "$SKIP_EXPORT" != "1" ]; then
    [ -n "$GODOT" ] && [ -x "$GODOT" ] || { echo "请用 GODOT_BIN 指定 Godot 可执行文件" >&2; exit 1; }
    echo "导入 core 资源 ..."
    "$GODOT" --headless --path "$CORE_DIR" --import >/dev/null || true
    echo "导出 Windows Desktop ..."
    "$GODOT" --headless --path "$CORE_DIR" --export-release "Windows Desktop" "$OUT/演播室2.exe"
    [ -f "$OUT/演播室2.exe" ] || { echo "缺少 exe" >&2; exit 1; }
    [ -f "$OUT/演播室2.pck" ] || { echo "缺少 pck" >&2; exit 1; }
fi

echo ""
echo "完成：$enabled 个插件 -> $OUT"
ls -1 "$OUT"
ls -1 "$OUT/mods" 2>/dev/null || true
