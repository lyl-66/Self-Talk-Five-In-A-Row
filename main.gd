extends Node2D

## 五子棋人机对战：玩家执黑先手，电脑执白。

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

@onready var board: Node2D = $Board
@onready var status_label: Label = $Status
@onready var restart_button: Button = $RestartButton

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

## 每次新开局自增；电脑等待结束后用它判断这一手是否已经作废。
var _game_id: int = 0


## 挂字体主题、接好信号，然后开一局。
func _ready() -> void:
	get_window().title = "五子棋 · 人机对战"
	_apply_ui_theme()
	board.point_clicked.connect(_on_board_point_clicked)
	restart_button.pressed.connect(new_game)
	new_game()


## 重开一局：清空棋盘、换掉电脑实例，并把那一手在途的定时器作废。
func new_game() -> void:
	_game_id += 1
	cells = PackedInt32Array()
	cells.resize(Gomoku.SIZE * Gomoku.SIZE)
	ai = GomokuAI.new(ai_player)
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


## 电脑的一手：先算出落点，再决定要不要「想一想」，然后落子。
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


## 落子并同步到视图，随后判定五连、满盘，最后交回合。
func _play(cell: Vector2i, player: int) -> void:
	cells[Gomoku.index(cell.x, cell.y)] = player
	board.place(cell, player)

	var line := Gomoku.find_win_line(cells, cell.x, cell.y, player)
	if not line.is_empty():
		game_over = true
		board.set_win_line(line)
		_set_input_enabled(false)
		_set_status("你赢了！" if player == human_player else "电脑赢了，再来一局？")
		return
	if Gomoku.is_full(cells):
		game_over = true
		_set_input_enabled(false)
		_set_status("棋盘已满，平局")
		return

	current_player = Gomoku.opponent(player)
	_set_status("轮到你（黑棋）" if current_player == human_player else "电脑思考中…")


## 开关棋盘输入。
func _set_input_enabled(enabled: bool) -> void:
	board.input_enabled = enabled


## 更新顶部那行提示文字。
func _set_status(text: String) -> void:
	status_label.text = text


## 给界面挂一个走系统中文字体的主题，否则默认字体会把汉字显示成方块。
func _apply_ui_theme() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONT_NAMES)
	font.allow_system_fallback = true
	var ui_theme := Theme.new()
	ui_theme.default_font = font
	ui_theme.default_font_size = 22
	status_label.theme = ui_theme
	restart_button.theme = ui_theme
