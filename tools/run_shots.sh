#!/usr/bin/env bash
# 跑 tools/shots.gd 截一套画面 PNG。用法：
#
#   bash tools/run_shots.sh
#
# 为什么需要这层包装：
#   1. shots.gd 接管窗口之前，main.gd 的 _ready() 会先按 windows.cfg 摆一次窗口。
#      存档里记的是一条 1546x1438 的大窗口，闪一下很难看。
#      所以这里临时换一份干净的 windows.cfg，跑完还原——这一步只能在进程外面做。
#   2. 顺手把四份存档都备份一遍。score.cfg / history.jsonl / settings.cfg 其实
#      shots.gd 自己会备份还原，这里是第二层：进程被 timeout 杀掉、脚本来不及收尾时兜底。
#
# 跑的时候屏幕上会真的出现窗口，持续几秒；悬停那张图会把光标挪到棋盘上再挪回来。

set -uo pipefail

GODOT="C:/Godot_v4.7.2-stable_win64_console.exe"
PROJECT="C:/godot/ai-tset"
UD="$APPDATA/Godot/app_userdata/Self-Talk-Five-In-A-Row"
FILES="score.cfg history.jsonl settings.cfg windows.cfg"
BACKUP="$(mktemp -d)"

restore() {
    for f in $FILES; do
        if [ -f "$BACKUP/$f" ]; then
            cp "$BACKUP/$f" "$UD/$f"
        elif [ -f "$UD/$f" ]; then
            # 跑之前没有、跑完冒出来的：删掉。
            # 存档目录是全新的时候（第一次启动或刚清空），不删的话一趟跑下来
            # 会凭空多出 score.cfg / history.jsonl，等于给玩家塞了两局脚本对局。
            rm -f "$UD/$f"
        fi
    done
    rm -rf "$BACKUP"
    echo "[run_shots] 存档已还原"
}
trap restore EXIT

for f in $FILES; do
    if [ -f "$UD/$f" ]; then
        cp "$UD/$f" "$BACKUP/$f"
    fi
done

cat > "$UD/windows.cfg" <<'EOF'
[meta]

version=2

[main]

position=Vector2i(20, 20)
size=Vector2i(720, 720)
visible=true

[score]

position=Vector2i(760, 20)
size=Vector2i(380, 400)
visible=false

[talk]

position=Vector2i(760, 20)
size=Vector2i(380, 400)
visible=false

[settings]

position=Vector2i(760, 20)
size=Vector2i(380, 400)
visible=false
EOF

timeout 120 "$GODOT" --path "$PROJECT" --script res://tools/shots.gd
echo "[run_shots] godot 退出码 $?"
ls -1 "$PROJECT/shots/"
