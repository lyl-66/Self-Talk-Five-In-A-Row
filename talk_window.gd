extends Window

## 对话窗口：独立的小窗口，对手每落一子在这里说一句话。
##
## 每局开一个新话题（main.gd 通过 start_topic 传进来）：
##   - 正文按顺序一句一句说，对手每落一子取一行；
##   - 正文说完了就从「垫场句池」里随机取，不会突然安静；
##   - 一局结束时清掉没说完的正文，再按本局的棋子数和胜负从对应档位随机说一句告别语。
## 日志每局清空，窗口底部显示当前话题。

## 被单独关掉时发出；主窗口据此把「对话窗口」按钮恢复成可点。
signal closed

## 日志最多保留多少行，超了从最老的开始丢。
const MAX_LINES: int = 200

## 没有台词文件时用的占位台词；真正的台词在 topics.txt 里。
const PLACEHOLDER_LINES: Array[String] = [
	"（占位台词）第 {move} 手，我落在 {cell}。",
	"（占位台词）嗯……第 {move} 手走 {cell}。",
	"（占位台词）该我了，第 {move} 手。",
]

@onready var log_label: RichTextLabel = $Column/Log
@onready var footer_label: Label = $Column/Footer

## 话题本，由主窗口在启动时接上。
var book: TopicBook = null

## 已经说过的台词，自己留一份，免得依赖 RichTextLabel 的内部内容。
var _lines: Array[String] = []
## 当前话题，以及它还没说完的正文。
var _topic: Dictionary = {}
var _body: Array = []
## 垫场句池（正文说完之后用）。
var _filler: Array = []
## 当前话题标题，显示在底部。
var _title: String = ""
## 这一局的告别语是否已经说过。
var _ended: bool = false
## 已经说过多少句。
var _spoken_count: int = 0
## 占位台词轮换用的下标。
var _placeholder_index: int = 0


## 接上关闭请求；只隐藏自己，日志留着。
func _ready() -> void:
	close_requested.connect(_on_close_requested)


## 开一局新话题：清空日志，把正文排队，记住垫场句池。
func start_topic(topic: Dictionary, filler_lines: Array) -> void:
	_topic = topic
	_body = (topic.get("body", []) as Array).duplicate()
	_filler = filler_lines.duplicate()
	_title = str(topic.get("title", ""))
	_ended = false
	_lines.clear()
	_spoken_count = 0
	_render()


## 对手每落一子说一句：正文优先，说完用垫场句，两者都没有才用占位台词。
func speak_move(move_number: int, cell: Vector2i, context: Dictionary = {}) -> void:
	if _ended:
		return
	var line := ""
	if not _body.is_empty():
		line = str(_body.pop_front())
	elif not _filler.is_empty():
		line = str(_filler[randi() % _filler.size()])
	else:
		line = _placeholder_line(move_number, cell)
	_append(_fill_vars(line, context))


## 一局结束：丢掉没说完的正文，按本局棋子数和胜负挑一档告别语，随机说一句。
## result 就是记分用的那个结果（"player" / "ai" / "draw"）。
## 这一档没写就往更大的档找；一档都没写就不说了（主窗口已经会显示胜负）。
func end_topic(final_stones: int, result: String, context: Dictionary = {}) -> void:
	_body.clear()
	if _ended:
		return
	_ended = true
	var candidates: Array = book.ending_lines(_topic, final_stones, result) if book != null else []
	if candidates.is_empty():
		_refresh_footer()
		return
	_append(_fill_vars(str(candidates[randi() % candidates.size()]), context))


## 正文里还剩几句没说。
func pending_count() -> int:
	return _body.size()


## 清空日志（不影响当前话题的进度）。
func clear_log() -> void:
	_lines.clear()
	_spoken_count = 0
	_render()


## 关闭按钮回调：隐藏窗口并通知主窗口。
func _on_close_requested() -> void:
	hide()
	closed.emit()


## 把 {变量} 换成实际值；上下文里没有的变量会原样留着，方便一眼看出漏了哪个。
func _fill_vars(line: String, context: Dictionary) -> String:
	if context.is_empty():
		return line
	return line.format(context)


## 取一条占位台词，每次换下一条。
func _placeholder_line(move_number: int, cell: Vector2i) -> String:
	var template: String = PLACEHOLDER_LINES[_placeholder_index % PLACEHOLDER_LINES.size()]
	_placeholder_index += 1
	return template.format({"move": move_number, "cell": Gomoku.cell_name(cell)})


## 把一句台词写进日志并刷新界面。
func _append(line: String) -> void:
	_lines.append(line)
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(_lines.size() - MAX_LINES)
	_spoken_count += 1
	_render()


## 把当前台词整块写进日志，并刷新底部状态。
func _render() -> void:
	log_label.text = "\n".join(PackedStringArray(_lines))
	_refresh_footer()


## 刷新底部那行状态：话题名 + 已说句数；台词文件有问题时把提示显示出来。
func _refresh_footer() -> void:
	var text := "已说 %d 句" % _spoken_count
	if not _title.is_empty():
		text = "话题：%s · %s" % [_title, text]
	if book != null and not book.last_error.is_empty():
		text += "  ⚠ %s" % book.last_error
	footer_label.text = text
