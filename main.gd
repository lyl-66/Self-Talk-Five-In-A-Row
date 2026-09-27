extends Node2D

## 五子棋人机对战：玩家执黑先手，电脑执白。
## 比分跨局累计并长期保存；电脑每落一子会在独立的对话窗口里说一句话；
## 电脑棋力（局面评估 / 两层搜索）与禁手规则、界面配色都在设置窗口里开关。

## 电脑思考时间的下限：开局这种平淡局面就等这么久。
const AI_THINK_DELAY_MIN: float = 0.1
## 电脑思考时间的上限：局面越紧张越接近它。
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
## 三个小窗口的存档名，摆放与记忆顺序都用它。
const SMALL_WINDOWS: Array[String] = ["score", "talk", "settings"]

@onready var board: Node2D = $Board
@onready var status_label: Label = $Status
@onready var settings_button: Button = $SettingsButton
@onready var score_button: Button = $ScoreButton
@onready var restart_button: Button = $RestartButton
@onready var talk_button: Button = $TalkButton
@onready var score_window: Window = $ScoreWindow
@onready var talk_window: Window = $TalkWindow
@onready var settings_window: Window = $SettingsWindow

## 玩家执黑，先手。
var human_player: int = Gomoku.BLACK
## 电脑执白。
var ai_player: int = Gomoku.WHITE

## 权威棋盘状态，取值见 Gomoku.EMPTY / BLACK / WHITE。
var cells: PackedInt32Array = PackedInt32Array()
## 电脑的走子逻辑，每局重新构造。
var ai: GomokuAI = null
## 当前该谁落子。
var current_player: int = Gomoku.BLACK
## 是否已经分出胜负或下满。
var game_over: bool = false

## 比分存档，启动时从用户目录读回，每局结束写回。
var store: ScoreStore = ScoreStore.new()
## 设置：棋力开关与配色，改动立刻写盘。
var settings: GameSettings = GameSettings.new()

## 每次新开局自增；电脑等待结束后用它判断这一手是否已经作废。
var _game_id: int = 0


## 读回设置与档案、挂字体主题、接好信号，把窗口摆回上次的位置，然后开一局。
## 窗口标题不写在这里，它跟着 project.godot 的 application/config/name 自动取。
func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_window().min_size = Vector2i(480, 480)
	get_window().close_requested.connect(_on_main_window_close_requested)
	settings.load_from_disk()
	store.load_from_disk()
	_apply_ui_theme()
	board.point_clicked.connect(_on_board_point_clicked)
	score_button.pressed.connect(_on_score_button_pressed)
	restart_button.pressed.connect(new_game)
	talk_button.pressed.connect(_on_talk_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	score_window.closed.connect(_on_score_window_closed)
	talk_window.closed.connect(_on_talk_window_closed)
	settings_window.closed.connect(_on_settings_window_closed)
	score_window.clear_requested.connect(_on_score_clear_requested)
	settings_window.settings_changed.connect(_on_settings_changed)
	settings_window.show_settings(settings)
	_apply_settings()
	# 先把位置和开关状态都定下来再显示，免得先闪一下在屏幕正中。
	_place_windows()
	# 窗口开着时对应按钮置灰；关掉就会重新可点。
	score_button.disabled = score_window.visible
	talk_button.disabled = talk_window.visible
	settings_button.disabled = settings_window.visible
	_refresh_score()
	new_game()


## 关主窗口时先把窗口布局存下来，再真正退出。
func _on_main_window_close_requested() -> void:
	_save_window_layout()
	get_tree().quit()


## 把三个小窗口当前的位置、尺寸和开关状态记进布局文件。
func _save_window_layout() -> void:
	WindowLayout.save_all({
		"main": get_window(),
		"score": score_window,
		"talk": talk_window,
		"settings": settings_window,
	})


## 摆窗口：上次记住过就回原位，没记住过就按默认位置摞在主窗口右边。
## 三个小窗口的开关状态也一起恢复：上次关着的，这次仍然关着。
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
		_:
			return settings_window


## 恢复小窗口的开关状态：记录里说关着就关着，没有记录就默认开着。
## 关着的时候主窗口对应按钮是可点的，随时能再打开。
func _apply_visibility(window: Window, record: Dictionary) -> void:
	window.visible = bool(record.get("visible", true))


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


## 重开一局：清空棋盘、换掉电脑实例，并把那一手在途的定时器作废。
## 比分和对话日志都跨局保留。
func new_game() -> void:
	_game_id += 1
	cells = PackedInt32Array()
	cells.resize(Gomoku.SIZE * Gomoku.SIZE)
	ai = GomokuAI.new(ai_player)
	ai.use_position_eval = settings.use_position_eval
	ai.use_search = settings.use_search
	current_player = human_player
	game_over = false
	board.hover_player = human_player
	board.reset()
	_set_input_enabled(true)
	_set_status("你执黑先手，点击棋盘落子")


## 玩家点棋盘：过滤掉不该接受的点击，落子后交给电脑应手。
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


## 点「比分窗口」：把被关掉的小窗口重新显示出来。
func _on_score_button_pressed() -> void:
	score_window.show()
	score_button.disabled = true
	_refresh_score()


## 点「对话窗口」：同样把它重新显示出来。
func _on_talk_button_pressed() -> void:
	talk_window.show()
	talk_button.disabled = true


## 点「设置」：先把当前设置刷进去，再显示出来。
func _on_settings_button_pressed() -> void:
	settings_window.show_settings(settings)
	settings_window.show()
	settings_button.disabled = true


## 比分窗口被单独关掉后，把按钮恢复成可点。
func _on_score_window_closed() -> void:
	score_button.disabled = false


## 对话窗口被单独关掉后，把按钮恢复成可点。
func _on_talk_window_closed() -> void:
	talk_button.disabled = false


## 设置窗口被单独关掉后，把按钮恢复成可点。
func _on_settings_window_closed() -> void:
	settings_button.disabled = false


## 比分窗口里确认清空比分：存档归零后立刻刷新界面。
func _on_score_clear_requested() -> void:
	store.clear()
	_refresh_score()


## 设置里改了东西：立刻写盘、立刻生效（棋力开关影响下一手，配色立刻重绘）。
func _on_settings_changed(new_settings: GameSettings) -> void:
	settings = new_settings
	settings.save()
	_apply_settings()


## 把设置应用到棋盘配色、窗口背景、文字明暗和电脑的走子参数上。
func _apply_settings() -> void:
	board.set_colors(settings.board_color, settings.line_color)
	RenderingServer.set_default_clear_color(settings.background_color)
	# 背景深浅可能变了，文字颜色要跟着重算
	_apply_ui_theme()
	if ai != null:
		ai.use_position_eval = settings.use_position_eval
		ai.use_search = settings.use_search


## 把当前比分和最近一局刷到比分窗口上。
func _refresh_score() -> void:
	score_window.set_score(store.player_wins, store.ai_wins, store.draw_count,
		store.games_played, store.last_game())


## 电脑的一手：先算出落点（顺便计时），再决定要不要「想一想」，然后落子、说一句话。
func _run_ai_turn() -> void:
	var token := _game_id
	_set_input_enabled(false)
	var started := Time.get_ticks_usec()
	var move := ai.choose_move(cells)
	settings_window.set_timing(int((Time.get_ticks_usec() - started) / 1000))
	if move.x < 0:
		return
	var delay := _think_delay(move)
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if token != _game_id or game_over:
		return
	_play(move, ai_player)
	# 每落一子说一句。想让「一段话分几手说完」，
	# 先 talk_window.queue_passage(整段话)，这里自然就会一次只取一行。
	talk_window.speak_move(_stone_count(), move)
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

	# 黑棋开着禁手时，只有「正好五连」才算胜：六连以上交给下面的禁手判罚
	var strict := settings.use_forbidden and player == human_player
	var line := Gomoku.find_win_line(cells, cell.x, cell.y, player, strict)
	if not line.is_empty():
		game_over = true
		board.set_win_line(line)
		_set_input_enabled(false)
		if player == human_player:
			store.player_wins += 1
			_set_status("你赢了！")
			_record_game("player")
		else:
			store.ai_wins += 1
			_set_status("电脑赢了，再来一局？")
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
			store.ai_wins += 1
			_set_status("禁手：%s · 黑棋判负" % foul)
			_record_game("ai")
			return

	if Gomoku.is_full(cells):
		game_over = true
		_set_input_enabled(false)
		store.draw_count += 1
		_set_status("棋盘已满，平局")
		_record_game("draw")
		return

	current_player = Gomoku.opponent(player)
	_set_status("轮到你（黑棋）" if current_player == human_player else "电脑思考中…")


## 一局收尾：追加一行明细、写回总分，再刷新窗口。
func _record_game(result: String) -> void:
	store.append_game(result, _stone_count())
	store.save_totals()
	_refresh_score()


## 数一数盘上已经有多少颗子，既当手数也算作下一句话的编号。
func _stone_count() -> int:
	var total := 0
	for value in cells:
		if value != Gomoku.EMPTY:
			total += 1
	return total


## 开关棋盘输入。
func _set_input_enabled(enabled: bool) -> void:
	board.input_enabled = enabled


## 更新顶部那行提示文字。
func _set_status(text: String) -> void:
	status_label.text = text


## 给界面挂一个走系统中文字体的主题，否则默认字体会把汉字显示成方块。
## 文字颜色按窗口背景的明暗自动取反——设置里把背景调成深色时，字也不会看不见。
## 主窗口和三个小窗口各是一套视口，都要挂上。
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
	# CheckButton 的开关底色是透明的，文字直接压在窗口背景上，必须跟着翻
	ui_theme.set_color("font_color", "CheckButton", text_color)
	ui_theme.set_color("font_hover_color", "CheckButton", text_color)
	ui_theme.set_color("font_pressed_color", "CheckButton", text_color)
	status_label.theme = ui_theme
	settings_button.theme = ui_theme
	score_button.theme = ui_theme
	restart_button.theme = ui_theme
	talk_button.theme = ui_theme
	score_window.theme = ui_theme
	talk_window.theme = ui_theme
	settings_window.theme = ui_theme
