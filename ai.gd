class_name GomokuAI
extends RefCounted

## 启发式五子棋 AI，棋力由外面的开关分三档：
##   1. 默认：五级硬规则 + 棋型分值 + 一步反制惩罚（快，每手十几毫秒）
##   2. use_position_eval：改用「我走完之后的局面分」来取舍
##   3. use_search：两层搜索（我一手 → 对手最好的应手 → 局面分），能挡住一手做成的四三

## 连五的分值，也就是一步定胜负。
const WIN_SCORE: int = 10_000_000
## 活四：两头都能成五，对手堵不住。
const OPEN_FOUR_SCORE: int = 1_000_000
## 冲四：一头被堵、下一手就能成五。
const FOUR_SCORE: int = 100_000
## 活三：再走一手就能变成活四。
const OPEN_THREE_SCORE: int = 50_000
## 活二：还早，但值得顺手做。
const OPEN_TWO_SCORE: int = 500

## 评估自己这一步的权重。
const ATTACK_WEIGHT: float = 1.0
## 评估堵住对手这一步的权重，略低于进攻，避免一味防守。
const DEFENSE_WEIGHT: float = 0.9
## 一步推演里对手应手的惩罚权重。
const RESPONSE_WEIGHT: float = 1.0
## 对手应手达到这个分值才计入惩罚，低于它的小便宜不理会。
const REPLY_THRESHOLD: int = FOUR_SCORE
## 一步推演最多考察多少个候选点，控制思考耗时。
const SEARCH_WIDTH: int = 16
## 两层搜索里对手应手的候选数，比我方少一些，控制叶子数量。
const REPLY_WIDTH: int = 8
## 候选点判定半径：离已有棋子超过这个距离的点不参与计算。
const NEIGHBOR_RADIUS: int = 2

## 局面评估里，多出来的复合威胁（从第二个活三算起）每个折算多少分。
const COMPOUND_BONUS: float = 30_000.0
## 局面评估里对手威胁的权重。
const EVAL_DEFENSE_WEIGHT: float = 1.0

## 开局压缩用的棋子数：盘上少于这么多子时，紧张度按比例打折。
const OPENING_STONES: float = 12.0
## 开局压缩的下限，保证第一手也留一点思考时间。
const OPENING_FLOOR: float = 0.15

## 窗口串里 X = 自己、O = 对手或棋盘外、. = 空点。
## 按威胁从大到小排列，每个方向只取第一个命中的棋型。
const PATTERNS: Array = [
	["XXXXX", WIN_SCORE],  # 连五
	[".XXXX.", OPEN_FOUR_SCORE],  # 活四
	["XXXX.", FOUR_SCORE],  # 冲四
	[".XXXX", FOUR_SCORE],
	["XXX.X", FOUR_SCORE],
	["X.XXX", FOUR_SCORE],
	["XX.XX", FOUR_SCORE],
	[".XXX.", OPEN_THREE_SCORE],  # 活三
	[".X.XX.", 30_000],  # 跳三
	[".XX.X.", 30_000],
	["OXXX.", 1_500],  # 眠三
	[".XXXO", 1_500],
	["XXX", 1_000],
	[".XX.", OPEN_TWO_SCORE],  # 活二
	["OXX.", 100],
	[".XXO", 100],
	["XX", 100],
	[".X.X.", 60],
	[".X.", 20],
	["X", 2],
]

var _me: int = Gomoku.WHITE
var _opp: int = Gomoku.BLACK

## 是否启用局面评估（设置窗口里的第二个开关）。
var use_position_eval: bool = false
## 是否启用两层搜索（设置窗口里的第三个开关）；打开时一定要用局面评估。
var use_search: bool = false


## 指定自己执哪一色，对手自动取另一色。
func _init(me: int) -> void:
	_me = me
	_opp = Gomoku.opponent(me)


## 选出这一手的落点；棋盘下满等无点可下时返回 (-1, -1)。
func choose_move(cells: PackedInt32Array) -> Vector2i:
	if not cells.has(Gomoku.BLACK) and not cells.has(Gomoku.WHITE):
		return Vector2i(Gomoku.SIZE / 2, Gomoku.SIZE / 2)

	var candidates := _collect_candidates(cells)
	if candidates.is_empty():
		return Vector2i(-1, -1)

	# 1. 自己能连五，直接赢。
	for cell in candidates:
		if _would_win(cells, cell, _me):
			return cell

	# 2. 对手能连五，必须堵。
	var five_threats := _filter(cells, candidates, _opp, WIN_SCORE)
	if not five_threats.is_empty():
		return _pick_best(cells, five_threats)

	# 3. 自己能做活四，对手堵不住。
	var open_fours := _filter(cells, candidates, _me, OPEN_FOUR_SCORE)
	if not open_fours.is_empty():
		return _pick_best(cells, open_fours)

	# 4. 对手能做活四：先用冲四抢先手，否则堵住。
	var opponent_open_fours := _filter(cells, candidates, _opp, OPEN_FOUR_SCORE)
	if not opponent_open_fours.is_empty():
		var fours := _filter(cells, candidates, _me, FOUR_SCORE)
		if not fours.is_empty():
			return _pick_best(cells, fours)
		return _pick_best(cells, opponent_open_fours)

	# 5. 以上都不适用，按开关决定怎么挑点。
	if use_search:
		return _search_two_ply(cells, candidates)
	if use_position_eval:
		return _pick_best_by_position(cells, candidates)
	return _pick_best(cells, candidates)


## 下在 cell 之后是否直接连成五子；上层用它判断这一手是不是决胜手。
func is_winning_move(cells: PackedInt32Array, cell: Vector2i) -> bool:
	return _would_win(cells, cell, _me)


## 下在 cell 之后对手是否会连成五子，也就是这一手是否在堵对手的五连。
func is_blocking_move(cells: PackedInt32Array, cell: Vector2i) -> bool:
	return _would_win(cells, cell, _opp)


## 估计当前局面的紧张程度，给上层决定思考时长用：
## 0.0 = 平淡的开局或残局，1.0 = 一步定胜负的关键处。
func estimate_tension(cells: PackedInt32Array) -> float:
	var best := 0
	var stones := 0
	for y: int in Gomoku.SIZE:
		for x: int in Gomoku.SIZE:
			if cells[Gomoku.index(x, y)] != Gomoku.EMPTY:
				stones += 1
				continue
			if not Gomoku.has_neighbor(cells, x, y, NEIGHBOR_RADIUS):
				continue
			var point := Vector2i(x, y)
			best = maxi(best, maxi(_score_at(cells, point, _me), _score_at(cells, point, _opp)))
	var opening := clampf(float(stones) / OPENING_STONES, OPENING_FLOOR, 1.0)
	return clampf(_threat_level(best) * opening, 0.0, 1.0)


## 局面评估：从 player 的角度给整个盘面打分，分数越高对 player 越有利。
## 主项是「双方一手能做出的最大棋型」；此外从第二个「能做活三以上的点」算起，
## 每个再加一份复合威胁分——两个活三远比一个活三可怕，靠主项是体现不出来的。
func evaluate_position(cells: PackedInt32Array, player: int) -> float:
	var rival := Gomoku.opponent(player)
	var my_best := 0
	var rival_best := 0
	var my_threats := 0
	var rival_threats := 0
	for y: int in Gomoku.SIZE:
		for x: int in Gomoku.SIZE:
			if cells[Gomoku.index(x, y)] != Gomoku.EMPTY:
				continue
			if not Gomoku.has_neighbor(cells, x, y, NEIGHBOR_RADIUS):
				continue
			var point := Vector2i(x, y)
			var mine := _score_at(cells, point, player)
			my_best = maxi(my_best, mine)
			if mine >= OPEN_THREE_SCORE:
				my_threats += 1
			var theirs := _score_at(cells, point, rival)
			rival_best = maxi(rival_best, theirs)
			if theirs >= OPEN_THREE_SCORE:
				rival_threats += 1
	var my_score := float(my_best) + float(maxi(0, my_threats - 1)) * COMPOUND_BONUS
	var rival_score := float(rival_best) + float(maxi(0, rival_threats - 1)) * COMPOUND_BONUS
	return my_score - rival_score * EVAL_DEFENSE_WEIGHT


## 一层 + 局面评估：只比「我下完之后，这个盘面对我有多好」。
func _pick_best_by_position(cells: PackedInt32Array, candidates: Array[Vector2i]) -> Vector2i:
	var board := cells.duplicate()
	var best: Vector2i = candidates[0]
	var best_value := -INF
	for cell in _top_candidates(cells, candidates, SEARCH_WIDTH):
		var at := Gomoku.index(cell.x, cell.y)
		board[at] = _me
		var value := evaluate_position(board, _me)
		board[at] = Gomoku.EMPTY
		if value > best_value:
			best_value = value
			best = cell
	return best


## 两层搜索：我先走一手，再假设对手挑「让我最差」的一手回应，取最坏情况最好的那手。
## alpha-beta：某个应手已经差过我目前最好的选择时，这个走法剩下的应手不必再看。
func _search_two_ply(cells: PackedInt32Array, candidates: Array[Vector2i]) -> Vector2i:
	var board := cells.duplicate()
	var best: Vector2i = candidates[0]
	var best_value := -INF
	for move in _top_candidates(cells, candidates, SEARCH_WIDTH):
		var my_at := Gomoku.index(move.x, move.y)
		board[my_at] = _me
		var worst := INF
		for reply in _top_replies(board, REPLY_WIDTH):
			var reply_at := Gomoku.index(reply.x, reply.y)
			board[reply_at] = _opp
			var value := evaluate_position(board, _me)
			board[reply_at] = Gomoku.EMPTY
			worst = minf(worst, value)
			if worst <= best_value:
				break
		board[my_at] = Gomoku.EMPTY
		if worst > best_value:
			best_value = worst
			best = move
	return best


## 按静态分排出前 count 个候选点，作为搜索里的走法池。
func _top_candidates(cells: PackedInt32Array, candidates: Array[Vector2i],
		count: int) -> Array[Vector2i]:
	var ranked: Array = []
	for cell in candidates:
		ranked.append({"cell": cell, "value": _static_value(cells, cell)})
	ranked.sort_custom(_by_value_desc)
	var top: Array[Vector2i] = []
	for i: int in mini(ranked.size(), count):
		top.append(ranked[i]["cell"])
	return top


## 站在对手的角度排出它最想下的前 count 手：它的进攻分 + 挡住我的价值。
## 对手能连五、或必须堵我的四时，这些手的分都很高，自然会排在前面。
func _top_replies(board: PackedInt32Array, count: int) -> Array[Vector2i]:
	var ranked: Array = []
	for cell in _collect_candidates(board):
		var attack := float(_score_at(board, cell, _opp))
		var deny := float(_score_at(board, cell, _me))
		ranked.append({"cell": cell, "value": attack + deny * DEFENSE_WEIGHT})
	ranked.sort_custom(_by_value_desc)
	var top: Array[Vector2i] = []
	for i: int in mini(ranked.size(), count):
		top.append(ranked[i]["cell"])
	return top


## 把所有空点里、附近有棋子的那些收集起来作为候选点。
func _collect_candidates(cells: PackedInt32Array) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for y: int in Gomoku.SIZE:
		for x: int in Gomoku.SIZE:
			if cells[Gomoku.index(x, y)] != Gomoku.EMPTY:
				continue
			if Gomoku.has_neighbor(cells, x, y, NEIGHBOR_RADIUS):
				candidates.append(Vector2i(x, y))
	return candidates


## 挑出在某个方向上能做出指定棋型的点（例如某一路是冲四、活四）。
func _filter(cells: PackedInt32Array, candidates: Array[Vector2i], player: int,
		wanted: int) -> Array[Vector2i]:
	var hits: Array[Vector2i] = []
	for cell in candidates:
		if _has_pattern(cells, cell, player, wanted):
			hits.append(cell)
	return hits


## 判断在 cell 落子后，四个方向里是否存在分值正好等于 wanted 的棋型。
func _has_pattern(cells: PackedInt32Array, cell: Vector2i, player: int, wanted: int) -> bool:
	for dir in Gomoku.DIRECTIONS:
		if _best_pattern(_window(cells, cell, dir, player)) == wanted:
			return true
	return false


## 先按静态分值排序，再对靠前的候选点推演对手的最佳应手：
## 只有对手一步就能拿到冲四以上的棋型时，才把这个成势空间扣掉。
func _pick_best(cells: PackedInt32Array, candidates: Array[Vector2i]) -> Vector2i:
	var ranked: Array = []
	for cell in candidates:
		ranked.append({"cell": cell, "value": _static_value(cells, cell)})
	ranked.sort_custom(_by_value_desc)

	var best: Vector2i = ranked[0]["cell"]
	var best_value := -INF
	for i: int in mini(ranked.size(), SEARCH_WIDTH):
		var cell: Vector2i = ranked[i]["cell"]
		var value := float(ranked[i]["value"]) - _counterplay_penalty(cells, cell)
		if value > best_value:
			best_value = value
			best = cell
	return best


## 算出下在 cell 之后、对手一步能拿到的最大分对应的惩罚值。
func _counterplay_penalty(cells: PackedInt32Array, cell: Vector2i) -> float:
	var reply := _best_reply_value(cells, cell)
	if reply < REPLY_THRESHOLD:
		return 0.0
	return RESPONSE_WEIGHT * float(reply)


## 排序回调：分值高的排前面。
func _by_value_desc(a: Dictionary, b: Dictionary) -> bool:
	return a["value"] > b["value"]


## 静态分值 = 自己这一步的收益 + 堵住对手的收益。
func _static_value(cells: PackedInt32Array, cell: Vector2i) -> float:
	var attack := float(_score_at(cells, cell, _me))
	var defense := float(_score_at(cells, cell, _opp))
	return attack * ATTACK_WEIGHT + defense * DEFENSE_WEIGHT


## 假设自己下在 cell，对手一步之内能拿到的最大攻击分。
func _best_reply_value(cells: PackedInt32Array, cell: Vector2i) -> int:
	var simulated := cells.duplicate()
	simulated[Gomoku.index(cell.x, cell.y)] = _me
	var best := 0
	for y: int in Gomoku.SIZE:
		for x: int in Gomoku.SIZE:
			if simulated[Gomoku.index(x, y)] != Gomoku.EMPTY:
				continue
			if not Gomoku.has_neighbor(simulated, x, y, NEIGHBOR_RADIUS):
				continue
			best = maxi(best, _score_at(simulated, Vector2i(x, y), _opp))
	return best


## 把分值折算成 0.0 ～ 1.0 的紧张度，档位对应棋型表里的威胁等级：
## 只有出现「下一步就能连五」才给满格，普通活三之类留出区分度。
func _threat_level(score: int) -> float:
	if score >= WIN_SCORE:
		return 1.0
	if score >= OPEN_FOUR_SCORE:
		return 0.75
	if score >= FOUR_SCORE:
		return 0.6
	if score >= OPEN_THREE_SCORE:
		return 0.4
	if score >= OPEN_TWO_SCORE:
		return 0.2
	return 0.1


## 判断在这里落子能否凑够五连（不去改棋盘，只数两个方向上的连子）。
func _would_win(cells: PackedInt32Array, cell: Vector2i, player: int) -> bool:
	for dir in Gomoku.DIRECTIONS:
		var count := 1
		count += _count_run(cells, cell, dir, 1, player)
		count += _count_run(cells, cell, dir, -1, player)
		if count >= 5:
			return true
	return false


## 从 from 出发沿 dir 的 sign 方向数连续的同色棋子个数。
func _count_run(cells: PackedInt32Array, from: Vector2i, dir: Vector2i, sign: int, player: int) -> int:
	var count := 0
	var x := from.x + dir.x * sign
	var y := from.y + dir.y * sign
	while Gomoku.in_bounds(x, y) and cells[Gomoku.index(x, y)] == player:
		count += 1
		x += dir.x * sign
		y += dir.y * sign
	return count


## 假设 player 下在 cell，累加四个方向各自的棋型分值。
func _score_at(cells: PackedInt32Array, cell: Vector2i, player: int) -> int:
	var total := 0
	for dir in Gomoku.DIRECTIONS:
		total += _best_pattern(_window(cells, cell, dir, player))
	return total


## 取以 cell 为中心、沿 dir 前后各 5 格的窗口串；中心格按 player 落子计算。
func _window(cells: PackedInt32Array, cell: Vector2i, dir: Vector2i, player: int) -> String:
	var chars := PackedStringArray()
	for step: int in range(-5, 6):
		if step == 0:
			chars.append("X")
			continue
		var x := cell.x + dir.x * step
		var y := cell.y + dir.y * step
		if not Gomoku.in_bounds(x, y):
			chars.append("O")
			continue
		var value := cells[Gomoku.index(x, y)]
		if value == Gomoku.EMPTY:
			chars.append(".")
		elif value == player:
			chars.append("X")
		else:
			chars.append("O")
	return "".join(chars)


## 在棋型表里从上往下找第一个命中的棋型，返回它的分值；都没有则 0 分。
func _best_pattern(window: String) -> int:
	for pattern in PATTERNS:
		if window.contains(pattern[0]):
			return int(pattern[1])
	return 0
