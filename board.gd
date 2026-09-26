extends Node2D

## 棋盘视图：只负责画棋盘/棋子并上报点击的交叉点，不含胜负逻辑。

## 玩家点了某个交叉点时发出，参数是格坐标（0 ～ 14）。
signal point_clicked(cell: Vector2i)

## 相邻两条线的间距（像素）。
const CELL: float = 36.0
## 棋盘外框到第一条线的留白（像素）。
const MARGIN: float = 32.0
## 棋子半径，略小于半格，避免相邻棋子粘在一起。
const STONE_RADIUS: float = CELL * 0.42
## 点击允许的偏移量，超过这个比例就认为没点中交叉点。
const CLICK_TOLERANCE: float = 0.45

const COLOR_BOARD := Color("e6c891")
const COLOR_BOARD_EDGE := Color("b08c56")
const COLOR_LINE := Color("4a3520")
const COLOR_BLACK_STONE := Color("1b1b1f")
const COLOR_WHITE_STONE := Color("f7f7f5")
const COLOR_WHITE_EDGE := Color(0.42, 0.42, 0.45, 0.85)
const COLOR_MARK := Color("d63b3b")

## 15 路棋盘上的五个星位：四角星加天元。
const STAR_POINTS: Array[Vector2i] = [
	Vector2i(3, 3), Vector2i(11, 3), Vector2i(3, 11), Vector2i(11, 11), Vector2i(7, 7),
]

## 棋盘整体边长（像素），由留白和格数算出来。
var board_size: float = MARGIN * 2.0 + CELL * float(Gomoku.SIZE - 1)

## 棋盘状态副本，取值见 Gomoku.EMPTY / BLACK / WHITE。
var cells: PackedInt32Array = PackedInt32Array()
## 悬停预览用哪种颜色的棋子，一般跟着玩家走。
var hover_player: int = Gomoku.BLACK
## 最后一手的坐标，用来画红点；(-1, -1) 表示还没落子。
var last_move: Vector2i = Vector2i(-1, -1)
## 获胜的那几个棋子坐标，非空时会套红圈。
var win_line: Array[Vector2i] = []

## 是否接受落子。关掉时同时清掉悬停预览，避免电脑思考时还显示预览子。
var input_enabled: bool = false:
	set(value):
		input_enabled = value
		_hover = Vector2i(-1, -1)
		queue_redraw()

var _hover: Vector2i = Vector2i(-1, -1)


## 初始化时先把棋盘清空，保证 _draw 有数据可画。
func _ready() -> void:
	reset()


## 清空棋盘、最后一手和获胜标记，回到开局状态。
func reset() -> void:
	cells = PackedInt32Array()
	cells.resize(Gomoku.SIZE * Gomoku.SIZE)
	last_move = Vector2i(-1, -1)
	win_line = []
	_hover = Vector2i(-1, -1)
	queue_redraw()


## 在视图里落下一颗子，并把它记成最后一手。
func place(cell: Vector2i, player: int) -> void:
	cells[Gomoku.index(cell.x, cell.y)] = player
	last_move = cell
	_hover = Vector2i(-1, -1)
	queue_redraw()


## 记录获胜的连子，让它们被红圈标出来。
func set_win_line(line: Array[Vector2i]) -> void:
	win_line = line
	queue_redraw()


## 每帧把鼠标位置换算成交叉点，只有变化时才重画，避免无意义的重绘。
func _process(_delta: float) -> void:
	var hover := Vector2i(-1, -1)
	if input_enabled:
		var cell := _to_cell(get_local_mouse_position())
		if cell.x >= 0 and cells[Gomoku.index(cell.x, cell.y)] == Gomoku.EMPTY:
			hover = cell
	if hover != _hover:
		_hover = hover
		queue_redraw()


## 处理左键点击：换算到交叉点，再交给外部决定能不能落子。
func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _to_cell(to_local(event.position))
		if cell.x >= 0 and cells[Gomoku.index(cell.x, cell.y)] == Gomoku.EMPTY:
			point_clicked.emit(cell)


## 按顺序画出：底板、格线、星位、棋子、悬停预览、最后一手标记、获胜红圈。
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(board_size, board_size)), COLOR_BOARD)
	draw_rect(Rect2(Vector2.ZERO, Vector2(board_size, board_size)), COLOR_BOARD_EDGE, false, 2.0)

	var edge := board_size - MARGIN
	for i: int in Gomoku.SIZE:
		var offset := MARGIN + CELL * float(i)
		draw_line(Vector2(MARGIN, offset), Vector2(edge, offset), COLOR_LINE, 1.0)
		draw_line(Vector2(offset, MARGIN), Vector2(offset, edge), COLOR_LINE, 1.0)
	draw_rect(Rect2(MARGIN, MARGIN, edge - MARGIN, edge - MARGIN), COLOR_LINE, false, 2.0)

	for star in STAR_POINTS:
		draw_circle(_to_position(star), 3.0, COLOR_LINE)

	for y: int in Gomoku.SIZE:
		for x: int in Gomoku.SIZE:
			var value := cells[Gomoku.index(x, y)]
			if value != Gomoku.EMPTY:
				_draw_stone(Vector2i(x, y), value)

	if _hover.x >= 0:
		_draw_hover(_hover)

	if last_move.x >= 0 and win_line.is_empty():
		draw_circle(_to_position(last_move), 3.5, COLOR_MARK)

	for cell in win_line:
		draw_arc(_to_position(cell), STONE_RADIUS + 2.0, 0.0, TAU, 32, COLOR_MARK, 2.5)


## 画一颗实心棋子，白子额外描一圈浅灰边，否则在木色底上看不清边界。
func _draw_stone(cell: Vector2i, player: int) -> void:
	var center := _to_position(cell)
	if player == Gomoku.BLACK:
		draw_circle(center, STONE_RADIUS, COLOR_BLACK_STONE)
	else:
		draw_circle(center, STONE_RADIUS, COLOR_WHITE_STONE)
		draw_arc(center, STONE_RADIUS - 0.75, 0.0, TAU, 32, COLOR_WHITE_EDGE, 1.5)


## 画鼠标悬停处的落子预览：半透明棋子加描边，和真棋子区分开。
func _draw_hover(cell: Vector2i) -> void:
	var center := _to_position(cell)
	var base := COLOR_BLACK_STONE if hover_player == Gomoku.BLACK else COLOR_WHITE_STONE
	draw_circle(center, STONE_RADIUS, Color(base, 0.4))
	draw_arc(center, STONE_RADIUS - 0.75, 0.0, TAU, 32, Color(base, 0.9), 1.5)


## 把格坐标换算成棋盘内的像素坐标（局部坐标）。
func _to_position(cell: Vector2i) -> Vector2:
	return Vector2(MARGIN + CELL * float(cell.x), MARGIN + CELL * float(cell.y))


## 把局部像素坐标换算成最近的交叉点；离交叉点太远或出界时返回 (-1, -1)。
func _to_cell(local_position: Vector2) -> Vector2i:
	var gx := (local_position.x - MARGIN) / CELL
	var gy := (local_position.y - MARGIN) / CELL
	var cell := Vector2i(roundi(gx), roundi(gy))
	if not Gomoku.in_bounds(cell.x, cell.y):
		return Vector2i(-1, -1)
	if absf(gx - float(cell.x)) > CLICK_TOLERANCE or absf(gy - float(cell.y)) > CLICK_TOLERANCE:
		return Vector2i(-1, -1)
	return cell
