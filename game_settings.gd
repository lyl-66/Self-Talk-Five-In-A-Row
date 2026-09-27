class_name GameSettings
extends RefCounted

## 设置存档：先手选择、电脑棋力的三个开关 + 三处配色。写在 user://settings.cfg。
## 写法沿用另外两套存档：先写 .tmp 再替换，读取一律容错
## （文件缺失、被改坏、类型不对，都回落成默认值）。

## 存档格式版本。
const VERSION: int = 1
## 设置文件路径。
const PATH: String = "user://settings.cfg"

## 棋盘底色默认值（和 board.gd 的默认值保持一致）。
const DEFAULT_BOARD_COLOR := Color("e6c891")
## 格线颜色默认值。
const DEFAULT_LINE_COLOR := Color("4a3520")
## 窗口背景色默认值（三个窗口共用）。
const DEFAULT_BACKGROUND_COLOR := Color(0.945, 0.933, 0.906)

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
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	player_goes_first = _pick_bool(config, "sides", "player_goes_first", player_goes_first)
	use_position_eval = _pick_bool(config, "ai", "position_eval", use_position_eval)
	use_search = _pick_bool(config, "ai", "two_ply_search", use_search)
	use_forbidden = _pick_bool(config, "rules", "forbidden", use_forbidden)
	board_color = _pick_color(config, "colors", "board", board_color)
	line_color = _pick_color(config, "colors", "line", line_color)
	background_color = _pick_color(config, "colors", "background", background_color)
	# 两层搜索离不开局面评估：读到不合法的组合就把它补上
	if use_search:
		use_position_eval = true


## 恢复默认值（不写盘）。
func reset_to_defaults() -> void:
	player_goes_first = true
	use_position_eval = false
	use_search = false
	use_forbidden = false
	board_color = DEFAULT_BOARD_COLOR
	line_color = DEFAULT_LINE_COLOR
	background_color = DEFAULT_BACKGROUND_COLOR


## 把当前设置写回磁盘：先写 .tmp 再替换，避免写一半断电把设置写花。
func save() -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "version", VERSION)
	config.set_value("sides", "player_goes_first", player_goes_first)
	config.set_value("ai", "position_eval", use_position_eval)
	config.set_value("ai", "two_ply_search", use_search)
	config.set_value("rules", "forbidden", use_forbidden)
	config.set_value("colors", "board", board_color)
	config.set_value("colors", "line", line_color)
	config.set_value("colors", "background", background_color)
	var temp_path := PATH + ".tmp"
	if config.save(temp_path) != OK:
		push_warning("设置写入失败：%s" % temp_path)
		return
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path),
			ProjectSettings.globalize_path(PATH)) != OK:
		push_warning("设置替换失败：%s" % PATH)


## 读一个布尔项；缺失或类型不对就用默认值。
func _pick_bool(config: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var value: Variant = config.get_value(section, key, fallback)
	return bool(value) if value is bool else fallback


## 读一个颜色项；缺失或类型不对就用默认值。
func _pick_color(config: ConfigFile, section: String, key: String, fallback: Color) -> Color:
	var value: Variant = config.get_value(section, key, fallback)
	return value if value is Color else fallback
