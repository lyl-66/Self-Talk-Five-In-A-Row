class_name Gomoku
extends RefCounted

## 五子棋规则：15x15 棋盘，黑先，横/竖/斜任意方向先连成五子者胜。
## 默认是自由规则（无禁手，长连也算胜）；开启禁手后黑棋按连珠规则判罚。

## 棋盘边长，单位是交叉点个数。
const SIZE: int = 15
## 空格标记。
const EMPTY: int = 0
## 黑棋标记，先手。
const BLACK: int = 1
## 白棋标记。
const WHITE: int = 2

## 四个成线方向：横、竖、右下斜、右上斜。
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(1, 1),
	Vector2i(1, -1),
]

## 判定「再补一子就能成五」时，沿方向最多看多远。
const REACH: int = 5


## 把交叉点坐标换算成 cells 数组里的下标。
static func index(x: int, y: int) -> int:
	return y * SIZE + x


## 判断坐标是否在棋盘范围内。
static func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < SIZE and y >= 0 and y < SIZE


## 取对手的棋子标记。
static func opponent(player: int) -> int:
	return WHITE if player == BLACK else BLACK


## 把格坐标说成人能看懂的样子，例如 (7, 3) → "H4"。台词和提示都会用到。
static func cell_name(cell: Vector2i) -> String:
	return "%s%d" % [String.chr("A".unicode_at(0) + cell.x), cell.y + 1]


## 棋盘上是否已经一个空点都不剩。
static func is_full(cells: PackedInt32Array) -> bool:
	return not cells.has(EMPTY)


## 判断某点附近 radius 格内有没有棋子，用来筛掉离棋堆太远的废点。
static func has_neighbor(cells: PackedInt32Array, x: int, y: int, radius: int) -> bool:
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			if dx == 0 and dy == 0:
				continue
			var nx := x + dx
			var ny := y + dy
			if in_bounds(nx, ny) and cells[index(nx, ny)] != EMPTY:
				return true
	return false


## 以 (x, y) 为最后一手检查是否连成五子，返回获胜的棋子坐标；未获胜返回空数组。
## exact_five 为 true 时只认「正好五连」：六连以上不算胜（黑棋开禁手时交给禁手判罚）。
static func find_win_line(cells: PackedInt32Array, x: int, y: int, player: int,
		exact_five: bool = false) -> Array[Vector2i]:
	for dir in DIRECTIONS:
		var line: Array[Vector2i] = [Vector2i(x, y)]
		for sign: int in [1, -1]:
			var step := 1
			while true:
				var nx := x + dir.x * step * sign
				var ny := y + dir.y * step * sign
				if not in_bounds(nx, ny) or cells[index(nx, ny)] != player:
					break
				line.append(Vector2i(nx, ny))
				step += 1
		if line.size() < 5:
			continue
		if exact_five and line.size() > 5:
			continue
		line.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.y < b.y if a.y != b.y else a.x < b.x)
		return line
	return []


## 判断黑棋下在 (x, y) 是否犯禁手，返回 "三三" / "四四" / "长连"；合法返回空串。
## 判定用的是连珠的定义本身：四 = 这条线再补一子就能成五；活三 = 再补一子就能成活四。
## 简化之处：不处理「假活三」（看着是活三、实际因为堵点变不成活四）这类细节。
static func forbidden_reason(cells: PackedInt32Array, x: int, y: int) -> String:
	# 允许这颗黑子已经落在盘上（_play 是先落子、再判罚），也允许是空点；
	# 只要不是白子就继续——下面统一在副本上把这颗黑子补上去再分析。
	if not in_bounds(x, y) or cells[index(x, y)] == WHITE:
		return ""
	var probe := cells.duplicate()
	probe[index(x, y)] = BLACK

	for dir in DIRECTIONS:
		if _run_through(probe, x, y, dir, BLACK) >= 6:
			return "长连"

	var fours := 0
	var open_threes := 0
	for dir in DIRECTIONS:
		if _five_points(probe, x, y, dir, BLACK).size() >= 1:
			fours += 1
		elif _makes_open_four(probe, x, y, dir, BLACK):
			open_threes += 1
	if fours >= 2:
		return "四四"
	if open_threes >= 2:
		return "三三"
	return ""


## 数 (x, y) 所在的那串同色子有几颗（含自己），只看一个方向，不改棋盘。
static func _run_through(cells: PackedInt32Array, x: int, y: int, dir: Vector2i, player: int) -> int:
	var total := 1
	for sign: int in [1, -1]:
		var step := 1
		while true:
			var nx := x + dir.x * step * sign
			var ny := y + dir.y * step * sign
			if not in_bounds(nx, ny) or cells[index(nx, ny)] != player:
				break
			total += 1
			step += 1
	return total


## 这个方向上，再补一子就能连五的所有空点（也就是这条线的「成五点」）。
## 会临时改动传入的 cells 并还原，调用方传副本进来。
static func _five_points(cells: PackedInt32Array, x: int, y: int, dir: Vector2i,
		player: int) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	for step: int in range(-REACH, REACH + 1):
		if step == 0:
			continue
		var px := x + dir.x * step
		var py := y + dir.y * step
		if not in_bounds(px, py) or cells[index(px, py)] != EMPTY:
			continue
		cells[index(px, py)] = player
		var reached := _run_through(cells, x, y, dir, player) >= 5
		cells[index(px, py)] = EMPTY
		if reached:
			points.append(Vector2i(px, py))
	return points


## 这个方向上是否「再补一子就能做出活四」——按连珠的定义，这就是活三。
static func _makes_open_four(cells: PackedInt32Array, x: int, y: int, dir: Vector2i,
		player: int) -> bool:
	for step: int in range(-REACH, REACH + 1):
		if step == 0:
			continue
		var px := x + dir.x * step
		var py := y + dir.y * step
		if not in_bounds(px, py) or cells[index(px, py)] != EMPTY:
			continue
		cells[index(px, py)] = player
		var becomes_open_four := _five_points(cells, x, y, dir, player).size() >= 2
		cells[index(px, py)] = EMPTY
		if becomes_open_four:
			return true
	return false
