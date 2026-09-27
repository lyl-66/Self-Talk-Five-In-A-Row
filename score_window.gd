extends Window

## 比分窗口：单独的一个小窗口，显示玩家与对手的胜场。
## 点它自己的关闭按钮只是隐藏，不销毁，所以主窗口能再把它打开。

## 被单独关掉时发出；主窗口据此把「比分窗口」按钮恢复成可点。
signal closed
## 用户确认要清空比分时发出；真正的清空动作由主窗口执行。
signal clear_requested

@onready var player_name_label: Label = $Column/Rows/PlayerName
@onready var opponent_name_label: Label = $Column/Rows/OpponentName
@onready var player_wins_label: Label = $Column/Rows/PlayerWins
@onready var opponent_wins_label: Label = $Column/Rows/OpponentWins
@onready var draw_label: Label = $Column/Rows/Draws
@onready var recent_label: Label = $Column/Tail/Recent
@onready var clear_button: Button = $Column/Tail/ClearButton
@onready var confirm_dialog: ConfirmationDialog = $Confirm

## 结果代号到中文的对照，用于「最近一局」那一行。
const RESULT_LABELS := {"player": "玩家胜", "ai": "对手胜", "draw": "和棋"}


## 接上信号；对话框内嵌在比分窗口里显示，不然会再蹦出一个系统窗口。
func _ready() -> void:
	gui_embed_subwindows = true
	close_requested.connect(_on_close_requested)
	clear_button.pressed.connect(_on_clear_button_pressed)
	confirm_dialog.confirmed.connect(_on_clear_confirmed)


## 按「玩家是否执黑」刷新两边的称呼（黑棋是先手）。
func set_sides(player_is_black: bool) -> void:
	player_name_label.text = "玩家（黑棋）" if player_is_black else "玩家（白棋）"
	opponent_name_label.text = "对手（白棋）" if player_is_black else "对手（黑棋）"


## 刷新三行比分数字和底部摘要。
func set_score(player_wins: int, ai_wins: int, draws: int, games: int, last: Dictionary) -> void:
	player_wins_label.text = str(player_wins)
	opponent_wins_label.text = str(ai_wins)
	draw_label.text = str(draws)
	recent_label.text = _format_recent(games, last)
	clear_button.disabled = games <= 0


## 关闭按钮回调：隐藏窗口并通知主窗口。
func _on_close_requested() -> void:
	hide()
	closed.emit()


## 点「清空」先弹确认框，避免误触把长期记录清掉。
func _on_clear_button_pressed() -> void:
	confirm_dialog.popup_centered()


## 确认框点了确定，交给主窗口去清空存档。
func _on_clear_confirmed() -> void:
	clear_requested.emit()


## 拼出底部那行摘要，例如「已保存 6 局 · 最近 玩家胜 43 手」。
func _format_recent(games: int, last: Dictionary) -> String:
	if games <= 0 or last.is_empty():
		return "还没有对局记录"
	var result := str(RESULT_LABELS.get(str(last.get("result", "")), "对局"))
	var text := "已保存 %d 局 · 最近 %s %d 手" % [games, result, int(last.get("moves", 0))]
	# 完整时间放进悬停提示，不占窗口宽度
	recent_label.tooltip_text = str(last.get("time", "")).replace("T", " ")
	return text
