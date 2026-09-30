extends Node2D

## 五子棋人机对战：默认玩家执黑先手、对手执白；先手可以在设置里对调
## （玩家改执白后手，对手执黑先下）。
## 比分跨局累计并长期保存；对手每落一子会在独立的对话窗口里说一句话，
## 台词按「每局一个话题」组织，话题写在 topics.txt 里（可以放在用户目录覆盖）。
## 对手的棋力（局面评估 / 两层搜索）与禁手规则、界面配色都在设置窗口里开关。

## 对手思考时间的下限：开局这种平淡局面就等这么久。
const AI_THINK_DELAY_MIN: float = 0.1
## 对手思考时间的上限：局面越紧张越接近它。
const AI_THINK_DELAY_MAX: float = 10.0
## 在基准时长上叠加的随机抖动，避免同一紧张度下每次等待都一样。
const AI_THINK_JITTER: float = 0.3
## 决胜手（自己这一手就能连五）只留这么一点停顿，让玩家先看清自己刚下的那颗子。
const AI_THINK_DELAY_FORCED: float = 0.15
## 必堵手（挡住对手连五）的思考时间下限：不算决胜，但也要看得出在犹豫。
const AI_THINK_DELAY_BLOCK_MIN: float = 0.4
## 必堵手的思考时间上限：比普通手短，避免每次都卡在同一个时长。
const AI_THINK_DELAY_BLOCK_MAX: float = 0.9

## 用于 UI 的中文字体候选，按优先级排列。
const FONT_NAMES: Array[String] = [
	"Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "SimHei", "sans-serif",
]
## 四个小窗口的存档名，摆放与记忆顺序都用它。
const SMALL_WINDOWS: Array[String] = ["score", "talk", "settings", "music"]
## 摆棋盘时上下各留出的高度：上面是状态行，下面是按钮行。
const TOP_BAND: float = 62.0
const BOTTOM_BAND: float = 56.0

## 落子音效。换文件改这里；找不到就静静地不响，不影响下棋。
const PLACE_SOUND_PATH: String = "res://sound/落子音效.mp3"
## 落子音效备几个播放器（队列，谁空着谁放）。
## 音效 0.211 秒，对手最快 0.1 秒就应手，所以最多两声重叠；备 4 个是留足余量。
const SFX_VOICES: int = 4
## 落子音效走的总线名（在 _build_sfx_bus() 里现建：一个垫静音的延时 + 一个彩蛋混响）。
const SFX_BUS: String = "Sfx"
## 落子音效前面垫的静音长度（毫秒），用总线上的延时实现。
##
## 干声那版的脆响就在最开头的 20 毫秒里。而"从第 3 颗子开始只听得见尾音、
## 听不见前面"这种症状，最典型的成因是：对手从那时起思考要好几秒，音频输出静了一阵，
## 重新出声时开头几十毫秒被削掉了（驱动或系统音效增强干的，发生在引擎之外——
## 我在送给设备之前的音频里验不出这个问题）。
##
## 所以把声音整体往后推这么多：要被削就先削这段静音，真正的脆响落在后面。
## 80 毫秒的延迟不可能听出来，画面上本来就有几十毫秒的视听容差。
const SFX_LEAD_IN_MS: float = 80.0

## 四个窗口的解锁顺序：赢第几把就解第几个。
## 也就是赢 1 把开对话、2 把开音乐、3 把开设置、4 把开比分。
const UNLOCK_ORDER: Array[String] = ["talk", "music", "settings", "score"]

## Shift+5「完全归档」要搬走的存档名单（都在 user:// 下）。
## 只搬认得出名字的这几份；logs/、着色器缓存那些目录一概不动。
const SAVE_FILES: Array[String] = ["settings.cfg", "score.cfg", "windows.cfg", "history.jsonl"]

@onready var board: Node2D = $Board
@onready var status_label: Label = $Status
@onready var settings_button: Button = $SettingsButton
@onready var music_button: Button = $MusicButton
@onready var button_row: HBoxContainer = $ButtonRow
@onready var score_button: Button = $ButtonRow/ScoreButton
@onready var restart_button: Button = $ButtonRow/RestartButton
@onready var talk_button: Button = $ButtonRow/TalkButton
@onready var score_window: Window = $ScoreWindow
@onready var talk_window: Window = $TalkWindow
@onready var settings_window: Window = $SettingsWindow
@onready var music_window: Window = $MusicWindow
@onready var music_player: AudioStreamPlayer = $MusicPlayer

## 落子音效的播放器**池**，队列式使用：谁空着谁放。
## 这样每一手都是一整段完整的音效，不会把上一声掐断。
## 在 _build_sfx_voices() 里现建，不放在场景里——数量是个实现细节，摆进场景反而要同步两处。
var sfx_players: Array[AudioStreamPlayer] = []

## 玩家执哪一色，由设置里的先手开关决定（每局开局时读一次）。
var human_player: int = Gomoku.BLACK
## 对手执另一色。
var ai_player: int = Gomoku.WHITE

## 权威棋盘状态，取值见 Gomoku.EMPTY / BLACK / WHITE。
var cells: PackedInt32Array = PackedInt32Array()
## 对手的走子逻辑，每局重新构造。
var ai: GomokuAI = null
## 当前该谁落子（黑棋永远先下）。
var current_player: int = Gomoku.BLACK
## 是否已经分出胜负或下满。
var game_over: bool = false

## 比分存档，启动时从用户目录读回，每局结束写回。
var store: ScoreStore = ScoreStore.new()
## 设置：先手、棋力开关与配色，改动立刻写盘。
var settings: GameSettings = GameSettings.new()
## 话题本：每局开一个话题，正文一句一句说，结束时按棋子数补一句告别。
var topic_book: TopicBook = TopicBook.new()

## 每次新开局自增；对手等待结束后用它判断这一手是否已经作废。
var _game_id: int = 0
## 本局用的话题，以及最后两手落在哪（台词里的 {cell} / {player_move} 要用）。
var _current_topic: Dictionary = {}
var _last_cell: Vector2i = Vector2i(-1, -1)
var _last_human_cell: Vector2i = Vector2i(-1, -1)


## 读回设置与档案、挂字体主题、接好信号，把窗口摆回上次的位置，然后开一局。
## 窗口标题不写在这里，它跟着 project.godot 的 application/config/name 自动取。
func _ready() -> void:
	_build_sfx_voices()
	get_tree().auto_accept_quit = false
	get_window().min_size = Vector2i(480, 480)
	get_window().close_requested.connect(_on_main_window_close_requested)
	get_viewport().size_changed.connect(_layout)
	settings.load_from_disk()
	store.load_from_disk()
	talk_window.book = topic_book
	music_window.attach_player(music_player)
	_load_place_sound()
	music_window.attach_sfx(sfx_players)
	_apply_ui_theme()
	board.point_clicked.connect(_on_board_point_clicked)
	score_button.pressed.connect(_on_score_button_pressed)
	restart_button.pressed.connect(new_game)
	talk_button.pressed.connect(_on_talk_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	music_button.pressed.connect(_on_music_button_pressed)
	score_window.closed.connect(_on_score_window_closed)
	talk_window.closed.connect(_on_talk_window_closed)
	settings_window.closed.connect(_on_settings_window_closed)
	music_window.closed.connect(_on_music_window_closed)
	score_window.clear_requested.connect(_on_score_clear_requested)
	settings_window.settings_changed.connect(_on_settings_changed)
	settings_window.show_settings(settings)
	_apply_settings()
	# 先把位置和开关状态都定下来再显示，免得先闪一下在屏幕正中。
	_place_windows()
	# 按累计胜场推进解锁进度，再把没解锁的窗口收起来、按钮置灰。
	_refresh_unlocks()
	_layout()
	_refresh_score()
	new_game()


## 视口尺寸变化时重摆主窗口里的东西。
## 注意：这些控件挂在 Node2D 下面，**锚点不起作用**（Godot 会按「父级尺寸为 0」算），
## 所以位置和宽度必须在这里算好，不能靠 anchors_preset。
func _layout() -> void:
	var view: Vector2 = get_viewport_rect().size
	var board_size: float = board.board_size

	# 顶部状态行：铺满整行，文字靠 Label 自己的居中对齐
	status_label.position = Vector2(20.0, 18.0)
	status_label.size = Vector2(maxf(200.0, view.x - 40.0), 44.0)

	# 棋盘：夹在状态行和按钮行之间居中
	var usable_top := TOP_BAND
	var usable_bottom: float = maxf(TOP_BAND + 1.0, view.y - BOTTOM_BAND)
	board.position = Vector2(
		(view.x - board_size) / 2.0,
		usable_top + maxf(0.0, (usable_bottom - usable_top - board_size) / 2.0))

	# 两个角按钮各贴自己那一侧的窗口边缘，互相镜像：
	# 「设置」在左上角固定离边 76（写在 main.tscn 里），「音乐」离右边缘也留同样多。
	#
	# 这里别拿棋盘的右边缘去定位——棋盘是居中的，窗口一变宽它就跟着跑，
	# 于是「音乐」会飘到离右边很远的地方：1100 宽的窗口里右边空出 274px，
	# 而左边的「设置」只离 76px，两个角严重不对称。
	# 贴窗口边缘才对：canvas_items 拉伸下画布单位按比例映射到屏幕像素，
	# 所以「固定的画布间距」在屏幕上就是「固定的比例位置」。
	var corner_size: Vector2 = settings_button.size
	music_button.size = corner_size
	music_button.position = Vector2(
		view.x - settings_button.position.x - corner_size.x, settings_button.position.y)

	# 底部按钮行：整行居中贴底
	var row_size: Vector2 = button_row.get_combined_minimum_size()
	button_row.size = row_size
	button_row.position = Vector2((view.x - row_size.x) / 2.0,
		view.y - BOTTOM_BAND + 6.0)


## 关主窗口时先把窗口布局存下来，再真正退出。
func _on_main_window_close_requested() -> void:
	_save_window_layout()
	get_tree().quit()


## 把四个小窗口当前的位置、尺寸和开关状态记进布局文件。
func _save_window_layout() -> void:
	WindowLayout.save_all({
		"main": get_window(),
		"score": score_window,
		"talk": talk_window,
		"settings": settings_window,
		"music": music_window,
	})


## 摆窗口：上次记住过就回原位，没记住过就按默认位置摞在主窗口右边。
## 四个小窗口的开关状态也一起恢复：上次关着的，这次仍然关着。
## 老存档里没有 [music] 这一段，就当没记录、走默认摆放。
func _place_windows() -> void:
	var layout := WindowLayout.load_all()
	if layout.has("main"):
		_restore_window(get_window(), layout["main"])
	var fallback := _default_side_positions(get_window())
	for key: String in SMALL_WINDOWS:
		var window := _small_window(key)
		_restore_window(window, layout.get(key, {}), fallback[key])
		_apply_visibility(window, layout.get(key, {}))


## 按存档名取小窗口。
func _small_window(key: String) -> Window:
	match key:
		"score":
			return score_window
		"talk":
			return talk_window
		"music":
			return music_window
		_:
			return settings_window


## 恢复小窗口的开关状态：记录里说关着就关着，没有记录就默认开着。
## 关着的时候主窗口对应按钮是可点的，随时能再打开。
## 注意：没解锁的窗口后面会被 _refresh_unlocks() 收起来，这里先按存档摆。
func _apply_visibility(window: Window, record: Dictionary) -> void:
	window.visible = bool(record.get("visible", true))


# --- 窗口解锁 ---------------------------------------------------------------

## 这个窗口解锁了没有。Shift+5 全开之后一律算解锁。
## UNLOCK_ORDER 里排在前面的一位对应「赢一把」，所以下标 0 的对话窗口需要 1 把。
func _is_unlocked(key: String) -> bool:
	if settings.unlock_all:
		return true
	return settings.unlock_level > UNLOCK_ORDER.find(key)


## 按累计胜场推进解锁进度，然后把没解锁的窗口收起来、按钮置灰。
## 解锁进度只增不减，所以清空比分不会把已经开出来的窗口又锁上。
##
## 这一把**刚开出来的**窗口会立刻弹到玩家面前：赢了之后只多出一个按钮
## 容易被忽略，跳出来才像"奖励到手"。**只弹这一次开出来的那些**——
## 已经开过的窗口不碰，玩家自己关掉的，不该赢一局又被掀开一次。
func _refresh_unlocks() -> void:
	var earned := mini(UNLOCK_ORDER.size(), store.player_wins)
	var before := settings.unlock_level
	if earned > settings.unlock_level:
		settings.unlock_level = earned
		settings.save()
	for key: String in UNLOCK_ORDER:
		if not _is_unlocked(key):
			_small_window(key).hide()
	_refresh_window_buttons()
	if settings.unlock_level > before:
		for i: int in range(before, settings.unlock_level):
			_small_window(UNLOCK_ORDER[i]).show()
		# 窗口刚变成显示，按钮要重算一次"已开着"的状态
		_refresh_window_buttons()


## 四个窗口入口按钮：**没解锁的直接不显示**——不给一个灰按钮占着位置，
## 免得新玩家一上来就看到四个点不动的按钮。解锁之后它才出现。
## 已经解锁但窗口开着的，显示但置灰（点开它再去点没意义）。
func _refresh_window_buttons() -> void:
	_apply_window_button(score_button, "score", score_window.visible)
	_apply_window_button(talk_button, "talk", talk_window.visible)
	_apply_window_button(settings_button, "settings", settings_window.visible)
	_apply_window_button(music_button, "music", music_window.visible)
	# 底部那一行是 HBoxContainer，按钮显不显示会改变整行宽度，
	# 所以要重新摆一次——它才会重新居中。
	_layout()


## 单个入口按钮的显示与可用状态。
func _apply_window_button(button: Button, key: String, window_open: bool) -> void:
	var unlocked := _is_unlocked(key)
	button.visible = unlocked
	button.disabled = not unlocked or window_open


## 两个隐藏组合键都在这儿处理，都是**按一下切过去、再按一下切回来**：
##   Shift+5  解锁全部 ←→ 完全归档（回到"从没玩过一把"）
##   Shift+6  落子音效加混响 ←→ 恢复干声
##
## 判断用的是**物理键位**而不是 keycode：这些组合打出来正好是 % ^ 这些符号，
## 而符号在不同键盘布局上按的键不一样，按物理位置才稳。
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or not key.shift_pressed:
		return
	match key.physical_keycode:
		KEY_5:
			_toggle_unlock_or_archive()
		KEY_6:
			_toggle_reverb_easter_egg()


## Shift+5：还没全开就全开，已经全开了就归档。
##
## 靠「现在是不是全开着」分辨该做哪件事，而不是另记一个开关——归档会把
## unlock_all 清掉，所以按键的语义和屏幕上看到的状态永远对得上。
## （赢棋自然全开时 unlock_all 还是 false，那就先按一次全开、再按一次归档。）
func _toggle_unlock_or_archive() -> void:
	if settings.unlock_all:
		_archive_everything()
	else:
		_unlock_everything()


func _unlock_everything() -> void:
	if not settings.unlock_all:
		settings.unlock_all = true
		settings.save()
	_refresh_unlocks()
	_set_status("已解锁全部窗口")


## 完全归档：把存档搬进 user://archive-<时间戳>/，游戏回到"从没玩过一把"。
##
## **是搬走，不是删除**——几份存档原样躺在那个目录里，想反悔手动挪回来就行。
## 搬完再把内存里的状态按"没有存档"重建一遍，顺序照抄 _ready()：
## 设置和比分重新读盘（文件没了 → 全默认），窗口回默认位置，
## 没解锁的窗口重新收起来，棋盘开新局。
func _archive_everything() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var dir_path := "user://archive-%s" % stamp
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path)) != OK:
		_set_status("归档失败：建不了 %s" % dir_path)
		return

	var moved := 0
	for file_name: String in _archivable_files():
		var from := ProjectSettings.globalize_path("user://%s" % file_name)
		var to := ProjectSettings.globalize_path("%s/%s" % [dir_path, file_name])
		if DirAccess.rename_absolute(from, to) == OK:
			moved += 1

	settings.load_from_disk()
	store.load_from_disk()
	_apply_settings()
	_place_windows()
	_refresh_unlocks()
	_layout()
	_refresh_score()
	new_game()
	_set_status("已完全归档 %d 份，从头开始（%s）" % [moved, dir_path])


## 归档要搬哪些文件：SAVE_FILES 那四份，加上历代「清空比分」留下的旧明细
## （它们平时躺在 user:// 根目录，不一起搬走就不算真的干净）。
func _archivable_files() -> Array[String]:
	var names: Array[String] = []
	for file_name: String in SAVE_FILES:
		if FileAccess.file_exists("user://%s" % file_name):
			names.append(file_name)
	var dir := DirAccess.open("user://")
	if dir == null:
		return names
	for file_name: String in dir.get_files():
		if file_name.begins_with("history-") and file_name.ends_with(".jsonl"):
			names.append(file_name)
	return names


## 默认位置：几个小窗口在主窗口右边竖排，右边放不下就挪到主窗口下面。
func _default_side_positions(main_window: Window) -> Dictionary:
	var gap := 12
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var need_width := 0
	var need_height := 0
	for key: String in SMALL_WINDOWS:
		var size := _small_window(key).size
		need_width = maxi(need_width, size.x)
		need_height += size.y
	need_height += gap * (SMALL_WINDOWS.size() - 1)

	var origin := Vector2i(main_window.position.x + main_window.size.x + gap,
		main_window.position.y)
	if origin.x + need_width > screen.position.x + screen.size.x:
		origin = Vector2i(main_window.position.x,
			main_window.position.y + main_window.size.y + gap)
	origin = _clamp_to_screen(origin, Vector2i(need_width, need_height))

	var positions := {}
	var y := origin.y
	for key: String in SMALL_WINDOWS:
		positions[key] = Vector2i(origin.x, y)
		y += _small_window(key).size.y + gap
	return positions


## 把窗口放回记录中的位置和大小；没有记录就退回默认位置。
func _restore_window(window: Window, record: Dictionary,
		fallback: Vector2i = Vector2i(-1, -1)) -> void:
	if record.has("size"):
		window.size = record["size"]
	if record.has("position"):
		window.position = _clamp_to_screen(record["position"], window.size)
	elif fallback.x >= 0:
		window.position = fallback


## 位置仍然落在某个显示器上就原样返回，否则夹回主显示器的可用区域，
## 免得拔掉副屏之后窗口开到看不见的地方。
func _clamp_to_screen(position: Vector2i, size: Vector2i) -> Vector2i:
	var rect := Rect2i(position, size)
	for index: int in DisplayServer.get_screen_count():
		if DisplayServer.screen_get_usable_rect(index).intersects(rect):
			return position
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	return Vector2i(
		clampi(position.x, screen.position.x,
			maxi(screen.position.x, screen.position.x + screen.size.x - size.x)),
		clampi(position.y, screen.position.y,
			maxi(screen.position.y, screen.position.y + screen.size.y - size.y)))


## 重开一局：按设置定下双方的颜色、清空棋盘、换掉对手实例、换一个话题。
## 玩家执白时由对手先下第一手。比分跨局保留，对话日志每局清空。
func new_game() -> void:
	_game_id += 1
	human_player = Gomoku.BLACK if settings.player_goes_first else Gomoku.WHITE
	ai_player = Gomoku.opponent(human_player)
	cells = PackedInt32Array()
	cells.resize(Gomoku.SIZE * Gomoku.SIZE)
	ai = GomokuAI.new(ai_player)
	ai.use_position_eval = settings.use_position_eval
	ai.use_search = settings.use_search
	ai.use_forbidden = settings.use_forbidden
	current_player = Gomoku.BLACK
	game_over = false
	_last_cell = Vector2i(-1, -1)
	_last_human_cell = Vector2i(-1, -1)
	board.hover_player = human_player
	board.reset()
	score_window.set_sides(human_player == Gomoku.BLACK)
	_refresh_score()
	_start_topic()

	if current_player == human_player:
		_set_input_enabled(true)
		_set_status("玩家执%s先手，点击棋盘落子" % _color_name(human_player))
	else:
		# 黑棋在对手手里，让它先下第一手
		_set_input_enabled(false)
		_set_status("玩家执%s后手，对手先下" % _color_name(human_player))
		_run_ai_turn()


## 开一局新话题：每次开局都重读台词文件（改完下一局就生效），然后挑一个。
##
## **对话窗口关着的时候什么都不做**——不开话题、不推进抽取进度，
## 免得玩家根本没看到对话，进度却已经走掉了。
## 关着也包括"还没解锁"（锁着的窗口一定是隐藏的），所以这里只看 visible 就够。
func _start_topic() -> void:
	topic_book.load_from_disk()
	if not _talk_open():
		_current_topic = {}
		talk_window.start_topic({}, [])
		return
	_current_topic = _pick_topic()
	talk_window.start_topic(_current_topic, topic_book.filler)


## 对话窗口现在开着吗。开着才说话题：玩家把窗口关了，对手就不该在背后自说自话，
## 也不该把话题进度吃掉。
func _talk_open() -> bool:
	return talk_window.visible


## 挑这一局说哪个话题：
##
##   1. 玩家赢过之后，下一局固定说「特别话题 N」（N = 是第几次赢，最多到 SPECIAL_SLOTS）。
##      靠 settings.special_played 保证每个只说一次——不能只看胜场：两胜之间胜场不变，
##      光看胜场会让同一个特别话题反复说。
##   2. 其余情况从普通话题里随机抽，一轮抽完之前不重复（洗牌袋在 settings 里）。
func _pick_topic() -> Dictionary:
	var wins: int = store.player_wins
	var spoken: int = settings.special_played
	if spoken < wins and spoken < topic_book.special_count():
		var special := topic_book.special_at(spoken + 1)
		if not special.is_empty():
			settings.special_played = spoken + 1
			settings.save()
			return special
	if topic_book.topic_count() == 0:
		return {}
	return topic_book.topic_at(settings.take_random_topic(topic_book.topic_count()))


## 玩家点棋盘：过滤掉不该接受的点击，落子后交给对手应手。
func _on_board_point_clicked(cell: Vector2i) -> void:
	if game_over or current_player != human_player:
		return
	var index := Gomoku.index(cell.x, cell.y)
	if cells[index] != Gomoku.EMPTY:
		return
	_play(cell, human_player)
	if game_over:
		return
	await _run_ai_turn()


## 点「比分窗口」：解锁了才开。没解锁时按钮本来就是灰的，这里是第二道保险。
func _on_score_button_pressed() -> void:
	if not _is_unlocked("score"):
		return
	score_window.show()
	_refresh_score()
	_refresh_window_buttons()


## 点「对话窗口」：同上。
func _on_talk_button_pressed() -> void:
	if not _is_unlocked("talk"):
		return
	talk_window.show()
	_refresh_window_buttons()


## 点「设置」：先把当前设置刷进去，再显示出来。
func _on_settings_button_pressed() -> void:
	if not _is_unlocked("settings"):
		return
	settings_window.show_settings(settings)
	settings_window.show()
	_refresh_window_buttons()


## 点「音乐」：显示播放器窗口。歌单由窗口自己在打开时重扫，这里不用管。
func _on_music_button_pressed() -> void:
	if not _is_unlocked("music"):
		return
	music_window.show()
	_refresh_window_buttons()


## 比分窗口被单独关掉后，按钮恢复成可点（前提是已解锁）。
func _on_score_window_closed() -> void:
	_refresh_window_buttons()


## 对话窗口被单独关掉后，按钮恢复成可点。
func _on_talk_window_closed() -> void:
	_refresh_window_buttons()


## 设置窗口被单独关掉后，按钮恢复成可点。
func _on_settings_window_closed() -> void:
	_refresh_window_buttons()


## 音乐窗口被单独关掉后，按钮恢复成可点。音乐本身不停，还在放。
func _on_music_window_closed() -> void:
	_refresh_window_buttons()


## 比分窗口里确认清空比分：存档归零后立刻刷新界面。
func _on_score_clear_requested() -> void:
	store.clear()
	_refresh_score()


## 设置里改了东西：立刻写盘、立刻生效。
## 先手开关按界面上的说明在下一局生效，其余（棋力、禁手、配色）立刻生效。
func _on_settings_changed(new_settings: GameSettings) -> void:
	settings = new_settings
	settings.save()
	_apply_settings()


## 把设置应用到棋盘配色、窗口背景、文字明暗和对手的走子参数上。
func _apply_settings() -> void:
	board.set_colors(settings.board_color, settings.line_color)
	RenderingServer.set_default_clear_color(settings.background_color)
	# 背景深浅可能变了，文字颜色要跟着重算
	_apply_ui_theme()
	if ai != null:
		ai.use_position_eval = settings.use_position_eval
		ai.use_search = settings.use_search
		ai.use_forbidden = settings.use_forbidden


## 把当前比分和最近一局刷到比分窗口上。
func _refresh_score() -> void:
	score_window.set_sides(human_player == Gomoku.BLACK)
	score_window.set_score(store.player_wins, store.ai_wins, store.draw_count,
		store.games_played, store.last_game())


## 对手的一手：先算出落点，再决定要不要「想一想」，然后落子、说一句话。
func _run_ai_turn() -> void:
	var token := _game_id
	_set_input_enabled(false)
	var move := ai.choose_move(cells)
	if move.x < 0:
		return
	var delay := _think_delay(move)
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if token != _game_id or game_over:
		return
	_play(move, ai_player)
	# 每落一子说一句：正文优先，正文说完就从垫场句池里取。
	# 窗口关着就一句都不说（玩家关了它，就不该在背后自说自话）。
	if _talk_open():
		talk_window.speak_move(_stone_count(), move, _talk_context())
	if not game_over:
		_set_input_enabled(true)


## 思考时长分三档：
## 决胜手（自己连五）只留一个短停顿；必堵手（挡住对手连五）稍作思考；
## 其余按局面紧张度在下限和上限之间取值，再叠一点抖动。
func _think_delay(move: Vector2i) -> float:
	if ai.is_winning_move(cells, move):
		return AI_THINK_DELAY_FORCED
	if ai.is_blocking_move(cells, move):
		return randf_range(AI_THINK_DELAY_BLOCK_MIN, AI_THINK_DELAY_BLOCK_MAX)
	var tension := ai.estimate_tension(cells)
	var base := lerpf(AI_THINK_DELAY_MIN, AI_THINK_DELAY_MAX, tension)
	return clampf(base + randf_range(-AI_THINK_JITTER, AI_THINK_JITTER),
		AI_THINK_DELAY_MIN, AI_THINK_DELAY_MAX)


## 落子并同步到视图，随后判定五连 / 禁手 / 满盘，记入比分，最后交回合。
func _play(cell: Vector2i, player: int) -> void:
	cells[Gomoku.index(cell.x, cell.y)] = player
	board.place(cell, player)
	_play_place_sound()
	_last_cell = cell
	if player == human_player:
		_last_human_cell = cell

	# 开着禁手时黑棋只有「正好五连」才算胜：六连以上交给下面的禁手判罚。
	# 注意禁手是绑黑棋的，不是绑玩家的——先后手可以对调。
	var strict := settings.use_forbidden and player == Gomoku.BLACK
	var line := Gomoku.find_win_line(cells, cell.x, cell.y, player, strict)
	if not line.is_empty():
		game_over = true
		board.set_win_line(line)
		_set_input_enabled(false)
		if player == human_player:
			store.player_wins += 1
			_set_status("玩家赢了！")
			_record_game("player")
		else:
			store.ai_wins += 1
			_set_status("对手赢了，再来一局？")
			_record_game("ai")
		return

	if strict:
		var foul := Gomoku.forbidden_reason(cells, cell.x, cell.y)
		if not foul.is_empty():
			game_over = true
			# 复用红圈标记指出犯规处：长连圈整串，三三/四四就圈这一颗
			var offender: Array[Vector2i] = Gomoku.find_win_line(cells, cell.x, cell.y,
				player, false)
			if offender.is_empty():
				offender.append(cell)
			board.set_win_line(offender)
			_set_input_enabled(false)
			if player == human_player:
				store.ai_wins += 1
				_set_status("禁手：%s · 玩家判负" % foul)
				_record_game("ai")
			else:
				store.player_wins += 1
				_set_status("禁手：%s · 对手判负" % foul)
				_record_game("player")
			return

	if Gomoku.is_full(cells):
		game_over = true
		_set_input_enabled(false)
		store.draw_count += 1
		_set_status("棋盘已满，平局")
		_record_game("draw")
		return

	current_player = Gomoku.opponent(player)
	if current_player == human_player:
		_set_status("轮到玩家（%s）" % _color_name(human_player))
	else:
		_set_status("对手思考中…")


## 一局收尾：追加一行明细、写回总分、结束本局话题（按棋子数和胜负补一句告别语）。
## 顺带按新的累计胜场推一次解锁进度——赢了这一把可能刚好开出下一个窗口。
func _record_game(result: String) -> void:
	store.append_game(result, _stone_count())
	store.save_totals()
	_refresh_score()
	if _talk_open():
		talk_window.end_topic(_stone_count(), result, _talk_context())
	_refresh_unlocks()


## 台词里能用的变量。落点统一写成 H8 这种样式，没落子时用破折号。
func _talk_context() -> Dictionary:
	return {
		"move": _stone_count(),
		"cell": Gomoku.cell_name(_last_cell) if _last_cell.x >= 0 else "—",
		"player_move": Gomoku.cell_name(_last_human_cell) if _last_human_cell.x >= 0 else "—",
		"my_score": store.ai_wins,
		"player_score": store.player_wins,
		"draws": store.draw_count,
		"topic": str(_current_topic.get("title", "")),
	}


## 数一数盘上已经有多少颗子，既当手数也算作下一句话的编号。
func _stone_count() -> int:
	var total := 0
	for value in cells:
		if value != Gomoku.EMPTY:
			total += 1
	return total


## 棋子颜色的中文名，拼提示语用。
func _color_name(player: int) -> String:
	return "黑棋" if player == Gomoku.BLACK else "白棋"


## 开关棋盘输入。
func _set_input_enabled(enabled: bool) -> void:
	board.input_enabled = enabled


## 更新顶部那行提示文字。
func _set_status(text: String) -> void:
	status_label.text = text


## 建落子音效的播放器池。在场景里只放一个"概念"，数量在代码里定——
## 摆进场景反而要两处同步，而且这几个节点纯粹是内部实现，没必要出现在场景树面板上。
func _build_sfx_voices() -> void:
	sfx_players.clear()
	for i: int in SFX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "SfxVoice%d" % (i + 1)
		add_child(voice)
		sfx_players.append(voice)


## 载入落子音效。文件不在或者加载不出来就只警告一声，不影响下棋。
func _load_place_sound() -> void:
	var stream: Resource = load(PLACE_SOUND_PATH) if ResourceLoader.exists(PLACE_SOUND_PATH) else null
	if not (stream is AudioStream):
		push_warning("落子音效读不到：%s（没有声音，但棋照下）" % PLACE_SOUND_PATH)
		return
	for voice: AudioStreamPlayer in sfx_players:
		voice.stream = stream
	_build_sfx_bus()


## 给落子音效建一条单独的总线：一个"垫静音"的延时 + 一个默认关着的混响。
##
## 效果 0 —— 延时，**默认生效**：把声音整体往后推 SFX_LEAD_IN_MS 毫秒
## （`dry = 0`，只放延时那一路，所以听感上就是晚一点响，音色不变）。
## 这是给"只听得见尾音、听不见前面"准备的护垫，理由写在那个常量旁边。
##
## 效果 1 —— 混响，**默认关着**，Shift+6 打开当彩蛋用。
## 当初为什么做了它：音效文件本身是个极短的脆响（峰值 1.19 已经削波，
## 但超过 -20dB 的部分只有 17 毫秒）——它不"轻"，是"太短"。
## 混响把可听时长从 17 毫秒拉到 113 毫秒，代价是听感发糊，所以只当彩蛋。
func _build_sfx_bus() -> void:
	if AudioServer.get_bus_index(SFX_BUS) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, SFX_BUS)

	var delay := AudioEffectDelay.new()
	delay.dry = 0.0
	delay.tap1_active = true
	delay.tap1_delay_ms = SFX_LEAD_IN_MS
	delay.tap1_level_db = 0.0
	# tap2 默认是**开着**的（500 毫秒后再响一次，-12dB）。只设 tap1 不管它的话，
	# 落子声后面会多出一声"重音"。反馈同理，一并关掉。
	delay.tap2_active = false
	delay.feedback_active = false
	AudioServer.add_bus_effect(index, delay)

	var reverb := AudioEffectReverb.new()
	reverb.predelay_msec = 10.0
	reverb.room_size = 0.3
	reverb.damping = 0.5
	reverb.wet = 0.6
	reverb.dry = 1.0
	AudioServer.add_bus_effect(index, reverb)
	AudioServer.set_bus_effect_enabled(index, 1, false)

	for voice: AudioStreamPlayer in sfx_players:
		voice.bus = SFX_BUS


## 彩蛋：把落子音效那层混响打开 / 关掉。
## （Shift+6，和 Shift+5 挨着，都是本机自己玩的口子。）
func _toggle_reverb_easter_egg() -> void:
	_build_sfx_bus()
	var index := AudioServer.get_bus_index(SFX_BUS)
	var was_on := AudioServer.is_bus_effect_enabled(index, 1)
	AudioServer.set_bus_effect_enabled(index, 1, not was_on)
	_set_status("落子音效：%s" % ("恢复干声" if was_on else "混响彩蛋"))


## 落一子，放一遍，**放完整的一整段**。
##
## 做法就是队列：从池子里挑一个**没在响的**播放器，让它从头放到尾。
## 这样每一手都是完整的一声脆响，不会像单播放器那样把上一声从中间掐断
## （音效 0.211 秒，而对手最快 0.1 秒就应手，两声必然撞上）。
##
## 池子里的都在响（理论上不会发生：对手最短也要想 0.1 秒，4 个够轮），
## 就把最快放完的那个顶掉——**宁可掐掉最旧的，也不让这一手没声音**。
##
## 音量走它们自己的播放器，和音乐窗口那条音乐音量互不影响。
func _play_place_sound() -> void:
	var voice := _take_free_voice()
	if voice != null:
		voice.play()


## 从池子里拿一个空着的播放器；都占着就返回最快放完的那个。
func _take_free_voice() -> AudioStreamPlayer:
	var busy: AudioStreamPlayer = null
	var busy_position := -1.0
	for candidate: AudioStreamPlayer in sfx_players:
		if candidate.stream == null:
			continue
		if not candidate.playing:
			return candidate
		var position := candidate.get_playback_position()
		if position > busy_position:
			busy = candidate
			busy_position = position
	return busy


## 给界面挂一个走系统中文字体的主题，否则默认字体会把汉字显示成方块。
## 文字颜色按窗口背景的明暗自动取反——设置里把背景调成深色时，字也不会看不见。
## 主窗口和四个小窗口各是一套视口，都要挂上。
func _apply_ui_theme() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONT_NAMES)
	font.allow_system_fallback = true
	var text_color := Color(0.23, 0.17, 0.11)
	if settings.background_color.get_luminance() <= 0.5:
		text_color = Color(0.91, 0.90, 0.88)
	var ui_theme := Theme.new()
	ui_theme.default_font = font
	ui_theme.default_font_size = 22
	ui_theme.set_color("font_color", "Label", text_color)
	ui_theme.set_color("default_color", "RichTextLabel", text_color)
	# Tree（音乐窗口的歌单）的文字色不在这里定：它压在什么颜色上由「界面控件」决定，
	# 所以归 _apply_control_color() 一起管，免得两边基准不一致。
	# CheckButton 的开关底色是透明的，文字直接压在窗口背景上，必须跟着翻
	ui_theme.set_color("font_color", "CheckButton", text_color)
	ui_theme.set_color("font_hover_color", "CheckButton", text_color)
	ui_theme.set_color("font_pressed_color", "CheckButton", text_color)
	# 弹窗（比分窗口那个「清空」确认框）自带的是 Godot 默认主题的深灰面板，
	# 而上面的文字颜色是给浅色背景准备的：深褐色的字压在深灰面板上对比度只有 1.3:1，
	# 基本看不清。给它换成和窗口同色的面板，字就落在自己该落的地方了。
	# 面板跟着背景走，所以背景调深时文字取反、面板也跟着变深，两边始终配套。
	var popup_panel := StyleBoxFlat.new()
	popup_panel.bg_color = settings.background_color
	popup_panel.border_color = text_color.lerp(settings.background_color, 0.72)
	popup_panel.set_border_width_all(1)
	popup_panel.set_corner_radius_all(6)
	popup_panel.set_content_margin_all(14)
	ui_theme.set_stylebox("panel", "AcceptDialog", popup_panel)
	_apply_control_color(ui_theme, text_color)
	status_label.theme = ui_theme
	settings_button.theme = ui_theme
	music_button.theme = ui_theme
	score_button.theme = ui_theme
	restart_button.theme = ui_theme
	talk_button.theme = ui_theme
	score_window.theme = ui_theme
	talk_window.theme = ui_theme
	settings_window.theme = ui_theme
	music_window.theme = ui_theme


## 按 settings.ui_color 给按钮 / 滑条 / 歌单换底色，并把控件上的文字调到看得清。
##
## 做法是拿**默认主题里那个样式框当模板，只换 bg_color**：边框、圆角、内边距都原样保留，
## 改的只有颜色。因为默认值 DEFAULT_UI_COLOR 就是默认主题用的那个深灰，不动这项设置时
## 这些替换等于原样重画，外观和以前一个像素都不差。
##
## 悬停 / 按下 / 禁用三个派生色的比例是照着默认主题反推的：
## 默认 normal 是 0.1，hover 是 0.225（相当于朝白色混 14%），pressed 是 0（RGB 归零），
## disabled 是 0.1 但 alpha 减半。
##
## 这里还有三件「不这么做就出事」的事，都在下面写了原因：
## 一是把半透明的控件色先合成成实色，二是堵住 CheckButton
## （否则 Button 的样式框会被它顺着继承链捡走），三是按钮文字按控件底色的明暗取反。
func _apply_control_color(ui_theme: Theme, text_color: Color) -> void:
	var ui := _solid_ui()
	var hover := ui.lerp(Color(1.0, 1.0, 1.0, ui.a), 0.14)
	var pressed := Color(ui.r * 0.35, ui.g * 0.35, ui.b * 0.35, ui.a)
	var disabled := Color(ui.r, ui.g, ui.b, ui.a * 0.5)
	ui_theme.set_stylebox("normal", "Button", _recolored_box("Button", "normal", ui))
	ui_theme.set_stylebox("hover", "Button", _recolored_box("Button", "hover", hover))
	ui_theme.set_stylebox("pressed", "Button", _recolored_box("Button", "pressed", pressed))
	ui_theme.set_stylebox("disabled", "Button", _recolored_box("Button", "disabled", disabled))

	var dark_ui := ui.get_luminance() <= 0.5

	# 主题查找会顺着类的继承链往上走，Button 的样式框会被 CheckButton 捡走，
	# 于是设置窗口里每行开关都糊上一块底色（默认值下也一样，属于外观回归）。
	# 把默认主题里 CheckButton 自己那套（全是空的）原样抄过来堵住。
	var default_theme := ThemeDB.get_default_theme()
	for item: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		ui_theme.set_stylebox(item, "CheckButton", default_theme.get_stylebox(item, "CheckButton"))

	# 按钮上的字得跟着控件底色走：底色深就照默认主题那套浅字，
	# 底色浅就换成窗口用的深字，否则把控件调成浅色之后字会看不见。
	for item: String in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		if dark_ui:
			ui_theme.set_color(item, "Button", default_theme.get_color(item, "Button"))
		else:
			ui_theme.set_color(item, "Button", text_color)

	# 滑条只换轨道；填充那一段按底色明暗取反——底色深就用白，底色浅就用黑，
	# 否则两种情况下总有一种看不见。默认底色（深）算出来正好是原来的白，外观不变。
	var fill := Color(1.0, 1.0, 1.0, 0.4) if dark_ui else Color(0.0, 0.0, 0.0, 0.35)
	ui_theme.set_stylebox("slider", "HSlider", _recolored_box("HSlider", "slider", ui))
	ui_theme.set_stylebox("grabber_area", "HSlider", _recolored_box("HSlider", "grabber_area", fill))

	# 歌单（Tree）：面板 + 选中行。
	#
	# 这里的文字色**必须跟面板走，不能跟窗口背景走**：面板底色来自「界面控件」，
	# 而控件色通常是深的（默认那个是 0.1 的深灰），窗口背景却可能是浅的。
	# 早先这里用了按窗口背景推出来的文字色，结果深褐色的字压在近黑的行底上，
	# 实测对比度只有 1.28:1 —— 基本看不见。
	var highlight := Color(1.0, 1.0, 1.0, 0.3) if dark_ui else Color(0.0, 0.0, 0.0, 0.25)
	ui_theme.set_stylebox("panel", "Tree", _recolored_box("Tree", "panel", ui))
	ui_theme.set_stylebox("selected", "Tree", _recolored_box("Tree", "selected", highlight))
	ui_theme.set_stylebox("selected_focus", "Tree",
		_recolored_box("Tree", "selected_focus", highlight))
	var on_panel := Color(1.0, 1.0, 1.0, 1.0) if dark_ui else text_color
	ui_theme.set_color("font_color", "Tree", on_panel)
	ui_theme.set_color("font_selected_color", "Tree", on_panel)
	ui_theme.set_color("font_hovered_color", "Tree", on_panel)


## 控件底色先和窗口背景合一次，得到一个实色。
##
## 默认那个控件色是半透明的（半透明才能和窗口背景融在一起），但半透明有两处不好对付：
## 一是取色器会把颜色量化成 8 位、alpha 直接拍平成 1，存回存档时半透明就没了；
## 二是「文字压在什么颜色上」得靠引擎怎么合成来猜。
## 所以干脆自己合：既让深浅判断有确定依据，也让不同控件之间的观感一致。
func _solid_ui() -> Color:
	var ui: Color = settings.ui_color
	var bg: Color = settings.background_color
	return Color(
		ui.r * ui.a + bg.r * (1.0 - ui.a),
		ui.g * ui.a + bg.g * (1.0 - ui.a),
		ui.b * ui.a + bg.b * (1.0 - ui.a),
		1.0)


## 拿默认主题的样式框当模板，只把底色换成 bg。
## 不是 StyleBoxFlat 的（比如 CheckButton 那个空的）返回 null，调用方自己看着办。
func _recolored_box(theme_type: String, item: String, bg: Color) -> StyleBoxFlat:
	var source: StyleBox = ThemeDB.get_default_theme().get_stylebox(item, theme_type)
	var box := source.duplicate() as StyleBoxFlat
	if box != null:
		box.bg_color = bg
	return box
