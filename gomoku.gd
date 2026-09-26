class_name Gomoku
extends RefCounted

## 五子棋规则：15x15 棋盘，黑先，横/竖/斜任意方向先连成五子者胜（自由规则，无禁手）。

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


## 把交叉点坐标换算成 cells 数组里的下标。
static func index(x: int, y: int) -> int:
	return y * SIZE + x


## 判断坐标是否在棋盘范围内。
static func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < SIZE and y >= 0 and y < SIZE


## 取对手的棋子标记。
static func opponent(player: int) -> int:
	return WHITE if player == BLACK else BLACK


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
static func find_win_line(cells: PackedInt32Array, x: int, y: int, player: int) -> Array[Vector2i]:
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
		if line.size() >= 5:
			line.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
				return a.y < b.y if a.y != b.y else a.x < b.x)
			return line
	return []
