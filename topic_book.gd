class_name TopicBook
extends RefCounted

## 话题本：把 res://topics.txt 里的台词读成一局一话题的剧本。
## 如果 user://topics.txt 存在就用它（方便你自己改台词，不用动工程文件）。
##
## 文件格式（详见 topics.txt 开头的说明）：
##   ### 话题：标题              开始一个话题
##   一行一句台词                 这一段是话题正文，对手每落一子说一句
##   === 垫场                     开始「正文说完之后的垫场句池」（全话题共用）
##   === 结束 32 玩家赢           开始「本局在 32 子以内结束、且玩家赢了」的告别语
##   === 结束 32 玩家输           同上，但玩家输了
##   === 结束 32                  不写胜负标记就是两种结果都能用的兜底句
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
const ENDING_TIERS: Array[int] = [10, 16, 24, 32, 64, 128, 256]
## 台词里认得的变量名，其余的花括号会当成笔误报出来。
const KNOWN_VARS: Array[String] = [
	"move", "cell", "player_move", "my_score", "player_score", "draws", "topic",
]
## 结束语行上能写的胜负标记 → 内部分类名。写在前面的优先匹配前缀。
const ENDING_LABELS: Dictionary = {
	"玩家赢": "player_win", "玩家胜": "player_win",
	"玩家输": "player_lose", "玩家败": "player_lose",
	"和棋": "draw", "平局": "draw", "和局": "draw",
}

## 每个话题：{ "title": String, "body": Array,
##             "endings": { 档位: { 胜负分类: Array } } }
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


## 按本局结束时的棋子数和胜负挑一档结束语：先在这一档里找「这个结果专用的」，
## 再找不带标记的兜底句；整档都没有就往更大的档找，都没有就返回空。
## result 取 main.gd 记分用的那几个值："player"（玩家赢）/ "ai"（对手赢）/ "draw"。
func ending_lines(topic: Dictionary, final_stones: int, result: String = "") -> Array:
	var endings: Dictionary = topic.get("endings", {})
	var key := outcome_key(result)
	for tier: int in ENDING_TIERS:
		if final_stones <= tier:
			var lines := _bucket(endings, tier, key)
			if not lines.is_empty():
				return lines
	for tier: int in ENDING_TIERS:
		var lines := _bucket(endings, tier, key)
		if not lines.is_empty():
			return lines
	return []


## 把记分用的结果名翻成结束语用的分类名。
static func outcome_key(result: String) -> String:
	match result:
		"player":
			return "player_win"
		"ai":
			return "player_lose"
		"draw":
			return "draw"
	return ""


## 取某一档里对某个结果该说的话：先找专用句，没有再退回不带标记的兜底句。
func _bucket(endings: Dictionary, tier: int, key: String) -> Array:
	var by_key: Dictionary = endings.get(tier, {})
	if not key.is_empty():
		var exact: Array = by_key.get(key, [])
		if not exact.is_empty():
			return exact
	return by_key.get("", [])


## 把七个档位写成「10/16/24/32/64/128/256」的样子，给提示信息用。
## 从 ENDING_TIERS 现算，改了档位不用再来改这句话。
static func tier_list_text() -> String:
	var parts := PackedStringArray()
	for tier: int in ENDING_TIERS:
		parts.append(str(tier))
	return "/".join(parts)


## 把行上写的胜负标记翻成内部分类名；认不出来返回 "?"。
func _label_key(label: String) -> String:
	if label.is_empty():
		return ""
	for name: String in ENDING_LABELS:
		if label.begins_with(name):
			return ENDING_LABELS[name]
	return "?"


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
	var ending_key := ""

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
			tier = 0
			ending_key = ""
			_check_vars(line_number, title)
			continue
		if line.begins_with("==="):
			var head := line.substr(3).strip_edges()
			if head.begins_with("垫场"):
				mode = "filler"
			elif head.begins_with("结束"):
				var parts := head.substr(2).strip_edges().replace("\t", " ").split(" ", false)
				tier = int(parts[0]) if not parts.is_empty() else 0
				var label := " ".join(parts.slice(1))
				ending_key = _label_key(label)
				if ending_key == "?":
					_note_issue(line_number, "认不出的胜负标记「%s」（写 玩家赢 / 玩家输 / 和棋，或者不写）" % label)
					ending_key = ""
				if not ENDING_TIERS.has(tier):
					_note_issue(line_number, "档位 %d 用不到（只能是 %s）" % [tier, tier_list_text()])
				if title.is_empty():
					_note_issue(line_number, "这段结束语没有话题（前面缺 `### 话题：标题`）")
				if not endings.has(tier):
					endings[tier] = {}
				var by_key: Dictionary = endings[tier]
				if not by_key.has(ending_key):
					by_key[ending_key] = []
				mode = "ending"
			else:
				_note_issue(line_number, "看不懂的分段标记「%s」" % line)
			continue
		_check_vars(line_number, line)
		match mode:
			"body":
				body.append(line)
			"ending":
				endings[tier][ending_key].append(line)
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
