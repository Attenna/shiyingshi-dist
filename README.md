# shiyingshi-dist — 演播室2 交付组装

把 **core 仓库**与各插件仓库按 `manifest.json` 组装成直播团队拿到的单一文件夹：

```
dist/
├── 演播室2.exe
├── 演播室2.pck
└── mods/
    ├── control_panel_base/
    ├── main_vision/
    ├── scene_manager_panel/
    └── streaming_arena/
```

交付结构与拆分前一致；`mods/` 是运行时的插件根目录（源码目录名为 `plugins/`）。

## 用法

```powershell
# Windows（需要 Godot 4.5.1 mono 与 4.5.1.stable.mono 导出模板）
.\scripts\assemble.ps1 -Godot "D:\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe"

# 只收集插件、不导出 exe/pck（本地快速检查）
.\scripts\assemble.ps1 -SkipExport
```

```bash
# Linux / macOS（需要 GODOT_BIN 指向 Godot 4.5.1 mono 可执行文件）
GODOT_BIN=/path/to/godot ./scripts/assemble.sh
```

产物在 `dist/`，每次运行会先清空 `.work/` 与 `dist/`，因此可重复执行。
除 exe/pck 内嵌时间戳外，相同输入（相同 ref）产出相同文件。

## manifest.json

```json
{
  "core":   { "repo": "...", "ref": "main", "subdir": "." },
  "plugins": [
    { "id": "...", "repo": "...", "ref": "main", "subdir": "plugins/<id>", "enabled": true }
  ]
}
```

- `ref` 可以是分支、tag 或 commit；
- `enabled: false` 的条目会被跳过并打印提示；
- **阶段 3 过渡**：插件暂时指向 core 仓库的 `plugins/<id>` 子目录；阶段 4 起改为各插件独立仓库 + tag；
- `player_database` 目前为 `enabled: false`：其源码尚未纳入仓库，待提交后启用（交付会变成 5 个插件）。

## CI

`.github/workflows/release.yml` 在 Windows runner 上安装 Godot 4.5.1 mono 与导出模板，
运行 `assemble.ps1` 并上传 `dist/` artifact。手动触发或推送 `v*` tag 时运行。
