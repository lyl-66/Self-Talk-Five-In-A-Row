class_name GameSettings
extends RefCounted

## 设置存档：先手选择、对手棋力的两个开关、禁手规则、四处配色，
## 另外还记两个「玩家看不见的进度」：话题轮换到哪了、窗口解锁到第几级。
## 写在 user://settings.cfg。
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
## 界面控件底色默认值。这个值不是随手挑的：Godot 默认主题里 Button / Tree / HSlider
## 的底就是 Color(0.1, 0.1, 0.1, 0.6)。拿它当默认值，不动这项设置时控件外观和原来
## 一个像素都不差——浅色窗口上合成出来正好是 #6F6E6B，就是现在那个灰。
const DEFAULT_UI_COLOR := Color(0.1, 0.1, 0.1, 0.6)

## 随机话题的「洗牌袋」：把话题编号打乱存成一袋，每次按顺序拿一个，
## 拿完重新洗。所以**一轮之内绝不重复**，换一轮才会重复。
## 袋子和进度都写进存档，关掉游戏再开是接着抽，不是从头来。
## 不是玩家可调项，只是需要跨次记住的进度。
var topic_bag: Array[int] = []
## 袋子里已经用到第几个。
var topic_bag_pos: int = 0

## 已经说过几个「特别话题」（0～5）。每赢一把之后的下一局固定说一个，
## 说过的不再说——所以不能只看胜场：胜场会在两次胜利之间一直不变，
## 光看胜场会让同一个特别话题反复说。
var special_played: int = 0

## 窗口解锁到第几级（0～4，对应赢了第几把）。同样是进度，不是玩家可调项。
##
## 单独记一份而不是直接用 store.player_wins：比分窗口的「清空」会把胜场归零，
## 那一下不能把已经开出来的窗口又锁回去。所以这个数只增不减。
var unlock_level: int = 0
## Shift+5 的应急通道：置位之后所有窗口都不再受 unlock_level 限制。
## 单独一个开关而不是直接把 unlock_level 顶到 4，是为了以后再加窗口时它也能开。
var unlock_all: bool = false

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
## 界面控件（按钮、滑条、歌单）的底色。文字颜色不在这里，仍按背景明暗自动取。
var ui_color: Color = DEFAULT_UI_COLOR


## 从磁盘读回设置；文件缺失或读不出来就保持默认值。
func load_from_disk() -> void:
	reset_to_defaults()
	topic_bag = []
	topic_bag_pos = 0
	special_played = 0
	unlock_level = 0
	unlock_all = false
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	topic_bag = ConfigStore.pick_int_array(config, "topics", "bag", [])
	topic_bag_pos = ConfigStore.pick_int(config, "topics", "bag_pos")
	special_played = ConfigStore.pick_int(config, "topics", "special_played")
	unlock_level = mini(4, ConfigStore.pick_int(config, "unlocks", "level"))
	unlock_all = ConfigStore.pick_bool(config, "unlocks", "all", false)
	player_goes_first = ConfigStore.pick_bool(config, "sides", "player_goes_first", player_goes_first)
	use_position_eval = ConfigStore.pick_bool(config, "ai", "position_eval", use_position_eval)
	use_search = ConfigStore.pick_bool(config, "ai", "two_ply_search", use_search)
	use_forbidden = ConfigStore.pick_bool(config, "rules", "forbidden", use_forbidden)
	board_color = ConfigStore.pick_color(config, "colors", "board", board_color)
	line_color = ConfigStore.pick_color(config, "colors", "line", line_color)
	background_color = ConfigStore.pick_color(config, "colors", "background", background_color)
	ui_color = ConfigStore.pick_color(config, "colors", "ui", ui_color)
	# 两层搜索离不开局面评估：读到不合法的组合就把它补上
	if use_search:
		use_position_eval = true


## 恢复默认值（不写盘）。只管设置窗口里列出来的那些项。
## 「随机话题抽到哪了」「已说了几个特别话题」和「窗口解锁到第几级」都是
## 玩家看不见的进度，不在这里归零——否则点一下「恢复默认」会把话题重新抽一遍、
## 把已开的窗口又锁上。
func reset_to_defaults() -> void:
	player_goes_first = true
	use_position_eval = false
	use_search = false
	use_forbidden = false
	board_color = DEFAULT_BOARD_COLOR
	line_color = DEFAULT_LINE_COLOR
	background_color = DEFAULT_BACKGROUND_COLOR
	ui_color = DEFAULT_UI_COLOR


## 随机抽一个话题编号，**一轮抽完之前不重复**（洗牌袋）。
##
## 每次从袋子里按顺序拿一个；拿完了重新洗一袋，所以只有换一轮才可能重复。
## 袋子存进存档，关掉游戏再开是接着抽。
func take_random_topic(count: int) -> int:
	if count <= 0:
		return 0
	# 话题可能被增删过，袋子里越界或重复的先剔掉，免得抽到不存在的话题
	var clean: Array[int] = []
	for index: int in topic_bag:
		if index >= 0 and index < count and not clean.has(index):
			clean.append(index)
	topic_bag = clean
	if topic_bag_pos >= topic_bag.size():
		# 新一轮。上一轮最后说的是哪个要记下来：
		# 洗牌是独立的，新一轮恰好从头一个就撞上上一轮结尾的概率不小，
		# 听感上就是"连着说了两遍同一个话题"。撞上就和第二个换个位置。
		var previous := topic_bag[topic_bag.size() - 1] if not topic_bag.is_empty() else -1
		topic_bag = []
		for i: int in count:
			topic_bag.append(i)
		topic_bag.shuffle()
		if topic_bag.size() > 1 and topic_bag[0] == previous:
			var swap := topic_bag[1]
			topic_bag[1] = topic_bag[0]
			topic_bag[0] = swap
		topic_bag_pos = 0
	var picked := topic_bag[topic_bag_pos]
	topic_bag_pos += 1
	return picked


## 把当前设置写回磁盘。写法和容错都在 ConfigStore 里。
func save() -> void:
	var config := ConfigFile.new()
	config.set_value("topics", "bag", topic_bag)
	config.set_value("topics", "bag_pos", topic_bag_pos)
	config.set_value("topics", "special_played", special_played)
	config.set_value("unlocks", "level", unlock_level)
	config.set_value("unlocks", "all", unlock_all)
	config.set_value("sides", "player_goes_first", player_goes_first)
	config.set_value("ai", "position_eval", use_position_eval)
	config.set_value("ai", "two_ply_search", use_search)
	config.set_value("rules", "forbidden", use_forbidden)
	config.set_value("colors", "board", board_color)
	config.set_value("colors", "line", line_color)
	config.set_value("colors", "background", background_color)
	config.set_value("colors", "ui", ui_color)
	ConfigStore.save_atomic(config, PATH)
