extends Window

## 对话窗口：独立的小窗口，对手每落一子就在这里说一句话。
## 和比分窗口一样，点它自己的关闭按钮只是隐藏，主窗口能再打开它。
##
## 「一段话分几手说完」的接口：用 queue_passage() 把一整段话排进队列，
## 之后 speak_move() 每次只从队列里取一行，剩下的留到后面的回合慢慢说；
## 队列空了就由占位台词顶上。

## 被单独关掉时发出；主窗口据此把「对话窗口」按钮恢复成可点。
signal closed

## 日志最多保留多少行，超了从最老的开始丢，免得长时间对局越堆越多。
const MAX_LINES: int = 200

## 占位台词池：现在内容不用管，以后把这里换成真正的台词就行。
## 用 {move} 表示第几手、{cell} 表示落在哪个点，一句里用不用哪个都可以。
const PLACEHOLDER_LINES: Array[String] = [
	"（占位台词）第 {move} 手，我落在 {cell}。",
	"（占位台词）嗯……第 {move} 手走 {cell}。",
	"（占位台词）该我了，第 {move} 手。",
]

@onready var log_label: RichTextLabel = $Column/Log
@onready var footer_label: Label = $Column/Footer

## 已经说过的台词，自己留一份，免得依赖 RichTextLabel 的内部内容。
var _lines: Array[String] = []
## 待说的台词队列：speak_move() 一次只取一行，剩下的留给后面的回合。
var _pending: Array[String] = []
## 已经说过多少句。
var _spoken_count: int = 0
## 占位台词轮换用的下标。
var _placeholder_index: int = 0


## 接上关闭请求；只隐藏自己，日志和队列都留着。
func _ready() -> void:
	close_requested.connect(_on_close_requested)


## 对手每落一子调用一次：队列里有排好的台词就说，没有就用占位台词顶上。
func speak_move(move_number: int, cell: Vector2i) -> void:
	var line: String
	if _pending.is_empty():
		line = _placeholder_line(move_number, cell)
	else:
		line = _pending.pop_front()
	_lines.append(line)
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(_lines.size() - MAX_LINES)
	_spoken_count += 1
	_render()


## 把一整段话排进队列：按换行拆成多行，之后每落一子只说一行。
## 这就是「以后可能一个回合只说一段话的一部分」的接口。
func queue_passage(passage: String) -> void:
	for raw: String in passage.split("\n"):
		var line := raw.strip_edges()
		if not line.is_empty():
			_pending.append(line)
	_refresh_footer()


## 队列里还排着多少行没说。
func pending_count() -> int:
	return _pending.size()


## 清空日志（队列不动），需要重新开始一段对话时调用。
func clear_log() -> void:
	_lines.clear()
	_spoken_count = 0
	_render()


## 关闭按钮回调：隐藏窗口并通知主窗口。
func _on_close_requested() -> void:
	hide()
	closed.emit()


## 取一条占位台词，每次换下一条，免得连续几手都一模一样。
func _placeholder_line(move_number: int, cell: Vector2i) -> String:
	var template: String = PLACEHOLDER_LINES[_placeholder_index % PLACEHOLDER_LINES.size()]
	_placeholder_index += 1
	return template.format({"move": move_number, "cell": _format_cell(cell)})


## 把 (7, 3) 这种格坐标说成人能看懂的样子，例如 H4。
func _format_cell(cell: Vector2i) -> String:
	return "%s%d" % [String.chr("A".unicode_at(0) + cell.x), cell.y + 1]


## 把当前台词整块写进日志，并刷新底部状态。
func _render() -> void:
	var parts := PackedStringArray()
	for line in _lines:
		parts.append("[color=#8a7a63]对手[/color]  %s" % line)
	log_label.text = "\n".join(parts)
	_refresh_footer()


## 刷新底部那行状态。
func _refresh_footer() -> void:
	var text := "已说 %d 句" % _spoken_count
	if not _pending.is_empty():
		text += " · 待说 %d 行" % _pending.size()
	footer_label.text = text
