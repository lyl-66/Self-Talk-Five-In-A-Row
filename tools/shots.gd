extends SceneTree

## 开发用截图工具：把主窗口和三个小窗口在各种状态下的画面存成 PNG，用来「真的看一眼」。
##
## 用法（**不要**加 --headless：headless 走的是 dummy 渲染驱动，_draw 根本不执行，拍出来是纯色空白）：
##
##   "C:/Godot_v4.7.2-stable_win64_console.exe" --path "C:/godot/ai-tset" --script res://tools/shots.gd
##
## 输出写在 res://shots/（已在 .gitignore 里忽略）。跑的时候屏幕上会真的出现窗口，持续几秒。
##
## 副作用要说清楚：这一趟会真的落子、真的记分，
## user:// 下的 score.cfg / history.jsonl / settings.cfg 都会被改写
## （settings.cfg 里的 [topics] next 每次开局都会动，score.cfg 会多出两局）。
## 所以 _run() 一进来就把这三份抄到 user://shots-backup/，退出前原样放回——
## 直接 --script 跑也是安全的，不依赖 run_shots.sh。
##
## run_shots.sh 另外管第四份 windows.cfg：那个必须在进程启动**之前**换掉
## （main.gd 的 _ready() 会先按它摆一次窗口，脚本拦不住），所以它留在脚本外面，
## 顺便在进程被 timeout 杀掉、脚本来不及收尾时兜底。

const OUT_DIR := "res://shots/"
const MAIN_POS := Vector2i(20, 20)
const MAIN_SIZE := Vector2i(720, 720)
const SMALL_POS := Vector2i(760, 20)
const SMALL_SIZE := Vector2i(380, 400)

## 这一趟会被改写的三份存档，进来先备份、退出前放回。
const USER_FILES: Array[String] = ["score.cfg", "history.jsonl", "settings.cfg"]
const BACKUP_DIR := "user://shots-backup"

## 开局头三手，纯粹为了让对话窗口里有几句话可拍。
const OPENING_CELLS: Array[Vector2i] = [
	Vector2i(7, 7), Vector2i(7, 8), Vector2i(8, 8),
]

var main = null
var _saved_mouse := Vector2i.ZERO
var _count := 0
## 开跑前就不存在的那些存档文件：跑完要删掉，不然会凭空留下一份（见 _restore_user_files）。
var _absent_files: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	print("[shots] user:// = ", OS.get_user_data_dir())
	print("[shots] screen0 usable = ", DisplayServer.screen_get_usable_rect(0))
	_snapshot_user_files()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	_saved_mouse = DisplayServer.mouse_get_position()
	_place(root, MAIN_POS, MAIN_SIZE, true)
	for key: String in ["score", "talk", "settings", "music"]:
		_place(_win(key), SMALL_POS, SMALL_SIZE, false)

	# 图要可复现，所以把会影响画面的设置钉回出厂值，别让玩家的 settings.cfg 决定
	# 图里写的是「玩家赢了」还是「对手赢了」、配色是不是他昨天调的那套。
	# new_game() 会按先手开关重算 human_player / ai_player，所以改完必须重开一局。
	# 这些改动只活在内存里，user:// 那份由 _restore_user_files() 收尾。
	_pin_settings()
	# 一趟要落十几颗子，把落子音效摘掉，不然截图过程一路噼里啪啦
	# （两个播放器都要摘：_play_place_sound() 会跳过 stream 为空的）
	for voice: AudioStreamPlayer in main.sfx_players:
		voice.stream = null

	for i: int in OPENING_CELLS.size():
		main.talk_window.speak_move(i + 1, OPENING_CELLS[i], main._talk_context())

	await _shot_fresh()
	await _shot_hover()
	await _shot_midgame()
	await _shot_win()
	await _shot_forbidden()
	await _shot_resized(1100, 700, "06-main-wide")
	await _shot_resized(480, 480, "07-main-small")

	_place(root, MAIN_POS, MAIN_SIZE, true)
	await _shot_score()
	await _shot_talk()
	await _shot_settings()
	await _shot_colorpicker()
	await _shot_confirm()
	await _shot_dark()
	await _shot_music()
	await _shot_custom_ui()

	root.warp_mouse(Vector2(_saved_mouse - root.position))
	_restore_user_files()
	print("[shots] done: %d png -> %s" % [_count, OUT_DIR])
	quit()


## 把这一趟会被改写的三份存档抄到 user://shots-backup/。要在 add_child 之前调，
## 否则 main.gd 的 _ready() 已经先写了一轮。
## 顺便记下哪些文件**本来就不存在**——那些跑完要删掉，不能只"还原已存在的"。
func _snapshot_user_files() -> void:
	_absent_files.clear()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BACKUP_DIR))
	for name: String in USER_FILES:
		var path := "user://" + name
		if FileAccess.file_exists(path):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(path),
				ProjectSettings.globalize_path(BACKUP_DIR + "/" + name))
		else:
			_absent_files.append(name)


## 放回原件，然后清掉备份。
##
## 本来不存在的文件要主动删掉：存档目录是全新的时候（第一次启动、或者刚清空过），
## 一趟跑下来会凭空生成 score.cfg / history.jsonl / windows.cfg，
## 只还原"已存在的"就会把它们留在玩家目录里——等于给玩家塞了两局脚本对局。
##
## 进程被强杀时走不到这里，user://shots-backup/ 会留着——手动抄回去就行。
func _restore_user_files() -> void:
	for name: String in USER_FILES:
		var backup := ProjectSettings.globalize_path(BACKUP_DIR + "/" + name)
		if FileAccess.file_exists(backup):
			DirAccess.copy_absolute(backup, ProjectSettings.globalize_path("user://" + name))
			var err := DirAccess.remove_absolute(backup)
			if err != OK:
				push_warning("[shots] 清备份 %s 失败：%d" % [name, err])
		elif _absent_files.has(name):
			var path := ProjectSettings.globalize_path("user://" + name)
			if FileAccess.file_exists(path):
				var del_err := DirAccess.remove_absolute(path)
				if del_err != OK:
					push_warning("[shots] 删掉这趟生成的 %s 失败：%d" % [name, del_err])
	var dir_err := DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_DIR))
	if dir_err != OK:
		push_warning("[shots] 清备份目录失败：%d" % dir_err)
	print("[shots] 存档已还原")


## 把影响画面的设置钉回出厂值并重开一局，让每次跑出来的图都一样。
## 玩家自己调过的先后手、棋力开关、配色都只留在 user:// 里，不进图。
func _pin_settings() -> void:
	main.settings.player_goes_first = true
	main.settings.use_position_eval = false
	main.settings.use_search = false
	main.settings.use_forbidden = false
	main.settings.board_color = GameSettings.DEFAULT_BOARD_COLOR
	main.settings.line_color = GameSettings.DEFAULT_LINE_COLOR
	main.settings.background_color = GameSettings.DEFAULT_BACKGROUND_COLOR
	# 窗口是按胜场逐个解锁的，截图要拍全部窗口，所以先把解锁全打开。
	# 这只活在内存里，user:// 那份由 _restore_user_files() 收尾。
	main.settings.unlock_all = true
	main._refresh_unlocks()
	main.settings_window.show_settings(main.settings)
	# 对话窗口是「关着就不说话题」的，而一局的话题在开局那一刻就定下来了。
	# 截图要拍对话窗口的内容，所以必须**先把它打开再开局**。
	main.talk_window.visible = true
	# new_game() 只重开一局，不负责把配色刷到棋盘和窗口上——那是 _apply_settings() 的事，
	# 少了这一步，前三张图还是玩家自己调的那套颜色。
	main._apply_settings()
	main.new_game()


# --- 各个场景 ---------------------------------------------------------------

## 开局空盘：关掉棋盘 _process，免得真实鼠标恰好停在交叉点上多出一颗预览子。
func _shot_fresh() -> void:
	main.board.set_process(false)
	main.board.reset()
	main.board.queue_redraw()
	main._set_input_enabled(true)
	main._set_status("玩家执黑先手，点击棋盘落子")
	await _shot(root, "01-main-fresh")


## 悬停预览：走真实输入路径——把光标真的挪到交叉点上，拍完再挪回原处。
func _shot_hover() -> void:
	main.board.set_process(true)
	await process_frame
	await process_frame
	var before := DisplayServer.mouse_get_position()
	root.warp_mouse(_board_point(Vector2i(7, 7)))
	for i: int in 5:
		await process_frame
	await _shot(root, "02-main-hover")
	root.warp_mouse(Vector2(before - root.position))
	main.board.set_process(false)


## 中局：16 颗子、没有任何五连，最后一手在 (6, 8)，红点会画在那里。
func _shot_midgame() -> void:
	var stones := [
		[Vector2i(7, 7), Gomoku.BLACK], [Vector2i(6, 6), Gomoku.BLACK],
		[Vector2i(8, 8), Gomoku.BLACK], [Vector2i(7, 5), Gomoku.BLACK],
		[Vector2i(5, 7), Gomoku.BLACK], [Vector2i(9, 7), Gomoku.BLACK],
		[Vector2i(6, 9), Gomoku.BLACK], [Vector2i(8, 5), Gomoku.BLACK],
		[Vector2i(7, 6), Gomoku.WHITE], [Vector2i(8, 6), Gomoku.WHITE],
		[Vector2i(6, 8), Gomoku.WHITE], [Vector2i(9, 8), Gomoku.WHITE],
		[Vector2i(5, 6), Gomoku.WHITE], [Vector2i(10, 7), Gomoku.WHITE],
		[Vector2i(6, 10), Gomoku.WHITE], [Vector2i(9, 5), Gomoku.WHITE],
	]
	_seed(stones, Vector2i(6, 8))
	main._set_status("轮到玩家（黑棋）")
	await _shot(root, "03-main-midgame")


## 玩家连成五子：走真正的 _play()，所以状态行、红圈、记分、告别语都是真的。
func _shot_win() -> void:
	_seed([
		[Vector2i(4, 7), Gomoku.BLACK], [Vector2i(5, 7), Gomoku.BLACK],
		[Vector2i(6, 7), Gomoku.BLACK], [Vector2i(7, 7), Gomoku.BLACK],
		[Vector2i(5, 6), Gomoku.WHITE], [Vector2i(6, 6), Gomoku.WHITE],
		[Vector2i(7, 6), Gomoku.WHITE], [Vector2i(3, 8), Gomoku.WHITE],
		[Vector2i(8, 8), Gomoku.WHITE],
	], Vector2i(7, 6))
	main._play(Vector2i(8, 7), Gomoku.BLACK)
	await _shot(root, "04-main-win")


## 禁手：黑棋走出长连立即判负，复用红圈指出犯规处。
## 黑棋先在 (3,7)~(5,7) 和 (7,7)~(9,7) 各躺三个，(6,7) 一落就把七颗连成一串。
func _shot_forbidden() -> void:
	main.settings.use_forbidden = true
	main._apply_settings()
	_seed([
		[Vector2i(3, 7), Gomoku.BLACK], [Vector2i(4, 7), Gomoku.BLACK],
		[Vector2i(5, 7), Gomoku.BLACK], [Vector2i(7, 7), Gomoku.BLACK],
		[Vector2i(8, 7), Gomoku.BLACK], [Vector2i(9, 7), Gomoku.BLACK],
		[Vector2i(4, 6), Gomoku.WHITE], [Vector2i(6, 6), Gomoku.WHITE],
		[Vector2i(8, 6), Gomoku.WHITE], [Vector2i(5, 9), Gomoku.WHITE],
	], Vector2i(8, 6))
	main._play(Vector2i(6, 7), Gomoku.BLACK)
	await _shot(root, "05-main-forbidden")


## 非正方形尺寸：验证棋盘重新居中、上下两行跟着挪、四周不留黑边。
func _shot_resized(width: int, height: int, name: String) -> void:
	root.size = Vector2i(width, height)
	for i: int in 5:
		await process_frame
	await _shot(root, name)


func _shot_score() -> void:
	main._on_score_button_pressed()
	_place(main.score_window, SMALL_POS, SMALL_SIZE, true)
	await _shot(main.score_window, "08-score")


func _shot_talk() -> void:
	main._on_talk_button_pressed()
	_place(main.talk_window, SMALL_POS, SMALL_SIZE, true)
	await _shot(main.talk_window, "09-talk")


func _shot_settings() -> void:
	main._on_settings_button_pressed()
	_place(main.settings_window, SMALL_POS, SMALL_SIZE, true)
	await _shot(main.settings_window, "10-settings")


## 取色器弹层：embed_subwindows=false，它也是一个独立系统窗口。
func _shot_colorpicker() -> void:
	var button: ColorPickerButton = main.settings_window.get_node("Column/Colors/BoardColor")
	button.get_popup().popup()
	for i: int in 5:
		await process_frame
	await _shot(button.get_popup(), "11-colorpicker")


## 比分窗口点「清空」弹的二次确认框，走真正的按钮回调。
func _shot_confirm() -> void:
	main.score_window._on_clear_button_pressed()
	for i: int in 4:
		await process_frame
	var dialog: Window = main.score_window.get_node("Confirm")
	await _shot(dialog, "12-score-confirm")
	dialog.hide()


## 深色背景：文字颜色按背景明暗自动取反（_apply_ui_theme 里那条 luminance 分支）。
## CheckButton 的文字是直接压在窗口背景上的，最容易看不见，所以连设置窗口一起拍。
func _shot_dark() -> void:
	var picker: Window = main.settings_window.get_node(
		"Column/Colors/BoardColor").get_popup()
	picker.hide()
	main.settings.background_color = Color("2b2b30")
	main._apply_settings()
	# 真实路径是「改色块 → settings_changed → 主窗口刷新」；这里直接改的值，
	# 得手动把设置窗口同步一遍，否则那三个色块显示的还是旧颜色。
	main.settings_window.show_settings(main.settings)
	_place(root, MAIN_POS, MAIN_SIZE, true)
	await _shot(root, "13-dark-main")
	await _shot(main.settings_window, "14-dark-settings")


## 音乐播放器窗口。深色那张把背景改暗了，先恢复出厂配色再拍，
## 否则拍出来是深色的，和另外几张没法比。
func _shot_music() -> void:
	main.settings.background_color = GameSettings.DEFAULT_BACKGROUND_COLOR
	main._apply_settings()
	main._on_music_button_pressed()
	_place(main.music_window, SMALL_POS, SMALL_SIZE, true)
	# 第一张拍文件夹收起的状态——这才是打开窗口时看到的样子
	await _shot(main.music_window, "15-music")
	# 再挑一首来放：正在放的那首会自动展开所在文件夹并选中
	main.music_window.play_index(0)
	await create_timer(1.5).timeout
	await _shot(main.music_window, "16-music-open")


## 把「界面控件」颜色改掉再拍设置窗口，确认按钮 / 滑条 / 歌单真的跟着变。
## 拍完恢复默认，免得影响后面（其实它是最后一张了，但别留坑）。
func _shot_custom_ui() -> void:
	main.settings.ui_color = Color(0.85, 0.30, 0.25)
	main._apply_settings()
	_place(main.settings_window, SMALL_POS, SMALL_SIZE, true)
	await _shot(main.settings_window, "17-ui-color")
	main.settings.ui_color = GameSettings.DEFAULT_UI_COLOR
	main._apply_settings()


# --- 零件 -------------------------------------------------------------------

## 直接摆一个局面：cells 和棋盘视图都写，不走胜负判定。
## last 是画红点的「最后一手」。
func _seed(stones: Array, last: Vector2i) -> void:
	var cells := PackedInt32Array()
	cells.resize(Gomoku.SIZE * Gomoku.SIZE)
	for stone: Array in stones:
		var cell: Vector2i = stone[0]
		cells[Gomoku.index(cell.x, cell.y)] = int(stone[1])
	main.cells = cells
	main.board.reset()
	main.board.cells = cells.duplicate()
	main.board.last_move = last
	main.board.queue_redraw()


## 等到真正画完一帧，再把该视口/窗口的内容存成 PNG。
func _shot(viewport: Viewport, name: String) -> void:
	for i: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	if image == null:
		print("[shots] !! %s: 没有拿到图像" % name)
		return
	var err := image.save_png(OUT_DIR + name + ".png")
	_count += 1
	print("[shots] %-18s %4d x %-4d err=%d" % [name, image.get_width(),
		image.get_height(), err])


## 交叉点在视口坐标里的位置（主窗口里的棋盘挂在 main 下面）。
func _board_point(cell: Vector2i) -> Vector2:
	return main.board.position + main.board._to_position(cell)


func _win(key: String) -> Window:
	match key:
		"score":
			return main.score_window
		"talk":
			return main.talk_window
		"music":
			return main.music_window
		_:
			return main.settings_window


func _place(window: Window, position: Vector2i, size: Vector2i, visible_now: bool) -> void:
	window.size = size
	window.position = position
	window.visible = visible_now
