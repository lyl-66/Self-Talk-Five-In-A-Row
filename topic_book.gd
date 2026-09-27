class_name TopicBook
extends RefCounted

## 话题本：把 res://topics.txt 里的台词读成一局一话题的剧本。
## 如果 user://topics.txt 存在就用它（方便你自己改台词，不用动工程文件）。
##
## 文件格式（详见 topics.txt 开头的说明）：
##   ### 话题：标题      开始一个话题
##   一行一句台词        这一段是话题正文，对手每落一子说一句
##   === 垫场            开始「正文说完之后的垫场句池」（全话题共用）
##   === 结束 32         开始「本局在 32 子以内结束时」的告别语
##
## 解析一律容错：空行和 `//` 注释忽略，缺哪一档结束语就退到写得有的一档，
## 整份文件读不出来时 topics 为空，上层会回落到占位台词。
## 解析中发现的问题（认不出的标记、用不到的档位、写错的变量名）会攒进 last_error，
## 由对话窗口显示在底部，作者不用去看控制台。

## 内置台词文件。
const BUILTIN_PATH: String = "res://topics.txt"
## 用户覆盖文件（存在就优先用它）。
const USER_PATH: String = "user://topics.txt"
## 结束语的档位上界（棋子数），和文件里 `=== 结束 N` 的 N 一一对应。
const ENDING_TIERS: Array[int] = [4, 8, 16, 32, 64, 128, 225]
## 台词里认得的变量名，其余的花括号会当成笔误报出来。
const KNOWN_VARS: Array[String] = [
	"move", "cell", "player_move", "my_score", "player_score", "draws", "topic",
]

## 每个话题：{ "title": String, "body": Array, "endings": { 档位: Array } }
var topics: Array = []
## 正文说完之后的垫场句池（全话题共用）。
var filler: Array = []
## 读文件时的提示，供界面显示；正常为空。
var last_error: String = ""
## 实际用的是哪个文件。
var source_path: String = ""
## 解析中攒下来的毛病（行号 + 说明），最后汇总成 last_error。
var _issues: Array[String] = []


## 从磁盘读一份剧本来；每次开新局都会重读，所以改完台词下一局就生效。
func load_from_disk() -> void:
	topics.clear()
	filler.clear()
	last_error = ""
	_issues.clear()
	source_path = USER_PATH if FileAccess.file_exists(USER_PATH) else BUILTIN_PATH
	var text := FileAccess.get_file_as_string(source_path)
	if text.is_empty():
		last_error = "读不到台词文件：%s" % source_path
		return
	_parse(text)
	if topics.is_empty():
		last_error = "台词文件里没有找到任何话题（要用 `### 话题：标题` 起头）：%s" % source_path
	elif not _issues.is_empty():
		last_error = _issue_summary()


## 一共写了几个话题。
func topic_count() -> int:
	return topics.size()


## 按轮换位置取一个话题；越界自动绕回，没有话题时返回空字典。
func topic_at(index: int) -> Dictionary:
	if topics.is_empty():
		return {}
	return topics[abs(index) % topics.size()]


## 按本局结束时的棋子数挑一档结束语；这一档没写就往更大的档找，都没有就返回空。
func ending_lines(topic: Dictionary, final_stones: int) -> Array:
	var endings: Dictionary = topic.get("endings", {})
	for tier: int in ENDING_TIERS:
		if final_stones <= tier and not (endings.get(tier, []) as Array).is_empty():
			return endings[tier]
	for tier: int in ENDING_TIERS:
		if not (endings.get(tier, []) as Array).is_empty():
			return endings[tier]
	return []


## 把攒下来的毛病拼成一句能显示在界面上的话（最多列三条，避免撑爆状态栏）。
func _issue_summary() -> String:
	var head: Array[String] = []
	for i: int in mini(3, _issues.size()):
		head.append(_issues[i])
	var text := "台词文件 %d 处问题 —— %s" % [_issues.size(), "；".join(head)]
	if _issues.size() > head.size():
		text += "；还有 %d 处" % (_issues.size() - head.size())
	return text


## 记一条毛病，同时打到控制台方便在编辑器里定位。
func _note_issue(line_number: int, message: String) -> void:
	var text := "第 %d 行 %s" % [line_number, message]
	_issues.append(text)
	push_warning(text)


## 把整份文本解析成话题列表。
func _parse(text: String) -> void:
	var title := ""
	var body: Array = []
	var endings: Dictionary = {}
	var mode := "filler"
	var tier := 0

	var lines := text.split("\n")
	for i: int in lines.size():
		var line := lines[i].strip_edges()
		var line_number := i + 1
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("###"):
			# 新话题：先把上一个存起来
			_store(title, body, endings)
			title = line.substr(3).strip_edges()
			if title.begins_with("话题"):
				title = title.substr(2).strip_edges()
			if title.begins_with("："):
				title = title.substr(1).strip_edges()
			body = []
			endings = {}
			mode = "body"
			_check_vars(line_number, title)
			continue
		if line.begins_with("==="):
			var head := line.substr(3).strip_edges()
			if head.begins_with("垫场"):
				mode = "filler"
			elif head.begins_with("结束"):
				tier = int(head.substr(2).strip_edges())
				if not ENDING_TIERS.has(tier):
					_note_issue(line_number, "档位 %d 用不到（只能是 4/8/16/32/64/128/225）" % tier)
				if title.is_empty():
					_note_issue(line_number, "这段结束语没有话题（前面缺 `### 话题：标题`）")
				if not endings.has(tier):
					endings[tier] = []
				mode = "ending"
			else:
				_note_issue(line_number, "看不懂的分段标记「%s」" % line)
			continue
		_check_vars(line_number, line)
		match mode:
			"body":
				body.append(line)
			"ending":
				endings[tier].append(line)
			_:
				filler.append(line)
	_store(title, body, endings)


## 找出句子里认不出的 {变量}，让作者能当场发现笔误。
func _check_vars(line_number: int, line: String) -> void:
	var from := 0
	while true:
		var open := line.find("{", from)
		if open < 0:
			return
		var close := line.find("}", open + 1)
		if close < 0:
			_note_issue(line_number, "有个 `{` 没有配上 `}`")
			return
		var name := line.substr(open + 1, close - open - 1)
		if not KNOWN_VARS.has(name):
			_note_issue(line_number, "不认得的变量 `{%s}`" % name)
		from = close + 1


## 把攒好的一个话题放进列表（没标题也没内容就丢掉）。
func _store(title: String, body: Array, endings: Dictionary) -> void:
	if title.is_empty() and body.is_empty() and endings.is_empty():
		return
	topics.append({"title": title, "body": body.duplicate(), "endings": endings.duplicate(true)})
