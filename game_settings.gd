class_name GameSettings
extends RefCounted

## 设置存档：先手选择、对手棋力的两个开关、禁手规则、三处配色，
## 另外还记一个「话题轮换到哪了」的进度。写在 user://settings.cfg。
## 写法沿用另外两套存档：先写 .tmp 再替换，读取一律容错
## （文件缺失、被改坏、类型不对，都回落成默认值），这些都走 ConfigStore。

## 设置文件路径。
const PATH: String = "user://settings.cfg"

## 棋盘底色默认值（和 board.gd 的默认值保持一致）。
const DEFAULT_BOARD_COLOR := Color("e6c891")
## 格线颜色默认值。
const DEFAULT_LINE_COLOR := Color("4a3520")
## 窗口背景色默认值（几个窗口共用）。
const DEFAULT_BACKGROUND_COLOR := Color(0.945, 0.933, 0.906)

## 话题轮换到的位置：不是玩家可调项，只是需要跨次记住的进度。
var next_topic: int = 0

## 玩家是否执黑先手；关掉就是玩家执白、对手执黑先下。默认开。
var player_goes_first: bool = true

## 是否启用局面评估（对手的棋力）。
var use_position_eval: bool = false
## 是否启用两层搜索；打开时局面评估一定也要开。
var use_search: bool = false
## 是否启用禁手规则（黑棋三三 / 四四 / 长连判负）。
var use_forbidden: bool = false

## 棋盘底色。
var board_color: Color = DEFAULT_BOARD_COLOR
## 格线颜色。
var line_color: Color = DEFAULT_LINE_COLOR
## 窗口背景色。
var background_color: Color = DEFAULT_BACKGROUND_COLOR


## 从磁盘读回设置；文件缺失或读不出来就保持默认值。
func load_from_disk() -> void:
	reset_to_defaults()
	next_topic = 0
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	next_topic = ConfigStore.pick_int(config, "topics", "next")
	player_goes_first = ConfigStore.pick_bool(config, "sides", "player_goes_first", player_goes_first)
	use_position_eval = ConfigStore.pick_bool(config, "ai", "position_eval", use_position_eval)
	use_search = ConfigStore.pick_bool(config, "ai", "two_ply_search", use_search)
	use_forbidden = ConfigStore.pick_bool(config, "rules", "forbidden", use_forbidden)
	board_color = ConfigStore.pick_color(config, "colors", "board", board_color)
	line_color = ConfigStore.pick_color(config, "colors", "line", line_color)
	background_color = ConfigStore.pick_color(config, "colors", "background", background_color)
	# 两层搜索离不开局面评估：读到不合法的组合就把它补上
	if use_search:
		use_position_eval = true


## 恢复默认值（不写盘）。只管设置窗口里列出来的那些项，
## 「话题轮换到哪了」是玩家看不见的进度，归零放在 load_from_disk() 里，
## 免得点一下「恢复默认」把话题悄悄退回第一个。
func reset_to_defaults() -> void:
	player_goes_first = true
	use_position_eval = false
	use_search = false
	use_forbidden = false
	board_color = DEFAULT_BOARD_COLOR
	line_color = DEFAULT_LINE_COLOR
	background_color = DEFAULT_BACKGROUND_COLOR


## 把当前设置写回磁盘。写法和容错都在 ConfigStore 里。
func save() -> void:
	var config := ConfigFile.new()
	config.set_value("topics", "next", next_topic)
	config.set_value("sides", "player_goes_first", player_goes_first)
	config.set_value("ai", "position_eval", use_position_eval)
	config.set_value("ai", "two_ply_search", use_search)
	config.set_value("rules", "forbidden", use_forbidden)
	config.set_value("colors", "board", board_color)
	config.set_value("colors", "line", line_color)
	config.set_value("colors", "background", background_color)
	ConfigStore.save_atomic(config, PATH)
