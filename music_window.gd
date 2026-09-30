extends Window

## 音乐播放器窗口：曲名、播放条、暂停/播放、下一首、歌单。
##
## 歌单有**两个来源**，合并成一个歌单列着：
##   · 玩家的 —— user://music/。**打包成 exe 之后这里依然能写**，是玩家加歌的地方；
##     窗口上那个「打开文件夹」按钮直接跳过去。
##   · 出厂的 —— 工程的 res://music/，跟着游戏一起打包的那批。
## 两边**同名的文件夹会并成一行**，里面玩家的歌排在出厂的歌前面；只在一边有的
## 文件夹就单独占一行。歌单**每次窗口打开时重新扫一遍**，所以往任一来源的子文件夹里
## 丢一首歌，下次开窗口它就在列表里——不用改代码，也不用重启。
##
## 出厂的歌在歌单里**压得更淡**，玩家自己放的和文件夹名一样亮，一眼看得出哪些是后加的。
##
## 歌单按文件夹分组：每个子文件夹一行（后面写着有几首），点一下展开或收起，
## 展开后才看得到里面的歌。空文件夹也列出来，展开写着「还没有歌」。
##
## 播放器不放在这个窗口里（由主窗口 attach_player 注入）：关掉窗口只是 hide()，
## 音乐要继续放，播放器挂在主窗口下面最稳。

## 被单独关掉时发出；主窗口据此把「音乐」按钮恢复成可点。
signal closed

## 出厂音乐的根目录，跟着游戏一起打包。子文件夹会被递归扫描。
const MUSIC_DIR: String = "res://music"
## 玩家自己的音乐目录，落在存档目录下。**导出成 exe 以后这里照样能写**，
## 而 res:// 在包里是只读的——所以玩家要加歌只能加在这儿。
const USER_MUSIC_DIR: String = "user://music"
## 两处来源的标记。歌单里是合并显示的，靠这个决定文字深浅和悬停说明。
const SOURCE_USER: String = "user"
const SOURCE_BUILTIN: String = "builtin"
## 运行时能加载的音频格式（Godot 4 只认这三种）。
const EXTENSIONS: Array[String] = ["mp3", "ogg", "wav"]
## 一首歌都没扫到时的提示。
const EMPTY_HINT: String = "没有找到歌曲：点下面的「打开文件夹」把音频放进去"

@onready var now_playing: Label = $Column/NowPlaying
@onready var progress: HSlider = $Column/Bar/Progress
@onready var clock: Label = $Column/Bar/Clock
@onready var volume_bar: HSlider = $Column/Volume/VolumeBar
@onready var sfx_bar: HSlider = $Column/Sfx/SfxBar
@onready var play_pause_button: Button = $Column/Buttons/PlayPause
@onready var next_button: Button = $Column/Buttons/Next
@onready var open_folder_button: Button = $Column/Buttons/OpenFolder
@onready var list: Tree = $Column/List

## 播放器，由主窗口注入。
var player: AudioStreamPlayer = null
## 游戏音效的播放器（落子声），同样由主窗口注入——它们挂主窗口下面，不归这个窗口。
## 是个数组：落子声备了两个轮流用，音效条要一起调，不然只有一半的声音受控。
var sfx_players: Array[AudioStreamPlayer] = []

## 播放顺序摊平之后的一份：顶层散歌在前，再按文件夹顺序接上各自的歌。
## 每项 { path, title, where, source }。_index 是它里面的下标，「下一首」也跟着它走。
var _tracks: Array[Dictionary] = []
## 歌单树的文件夹，每项 { name, tracks }。两处来源同名的会并成一条；
## 空文件夹也在里面（tracks 为空）。
var _folders: Array[Dictionary] = []
## 直接放在任一根目录下、没进子文件夹的歌。玩家的排在前面。
var _root_tracks: Array[Dictionary] = []
## 哪些文件夹被用户展开过。重扫之后照这个恢复，不然每次开窗口都缩回去。
var _expanded: Dictionary = {}
## 路径 -> TreeItem，播放时用来把正在放的那首选中。
var _item_by_path: Dictionary = {}
## 正在重建歌单树时置位：程序选中行也会触发 item_selected，得挡掉。
var _rebuilding: bool = false
## 当前选中第几首；-1 表示还没选。
var _index: int = -1
## 当前这首歌的 res:// 路径。重扫歌单后靠它把正在放的那首找回来。
var _current_path: String = ""
## 正在拖播放条：拖动过程中不 seek，松手才定位，免得一卡一卡。
var _dragging: bool = false
## 音乐音量（0..1 线性），记住是为了 attach_player 时能补上。
var _volume: float = 1.0
## 音效音量（0..1 线性），同理。
var _sfx_volume: float = 1.0
## 出错时显示在曲名那一行。
var _error: String = ""


func _ready() -> void:
	close_requested.connect(_on_close_requested)
	play_pause_button.pressed.connect(toggle_pause)
	next_button.pressed.connect(play_next)
	open_folder_button.pressed.connect(_on_open_folder_pressed)
	list.item_selected.connect(_on_item_selected)
	progress.value_changed.connect(_on_progress_changed)
	progress.drag_started.connect(_on_progress_drag_started)
	progress.drag_ended.connect(_on_progress_drag_ended)
	volume_bar.value_changed.connect(_on_volume_changed)
	volume_bar.value = _volume
	sfx_bar.value_changed.connect(_on_sfx_volume_changed)
	sfx_bar.value = _sfx_volume
	_ensure_user_dir()
	reload_playlist()


## 把玩家的音乐目录建出来（已经有了就什么都不做）。
## 一进来就建，玩家点「打开文件夹」时那个目录一定在，不会扑空。
func _ensure_user_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_MUSIC_DIR))


## 点「打开文件夹」：用系统自带的文件管理器打开玩家的音乐目录。
## 路径藏在 AppData 深处，指望玩家自己找到是不现实的，所以给个按钮。
func _on_open_folder_pressed() -> void:
	_ensure_user_dir()
	var err := OS.shell_open(ProjectSettings.globalize_path(USER_MUSIC_DIR))
	if err != OK:
		_error = "打不开文件夹：%s" % USER_MUSIC_DIR
		_refresh_now_playing()


## 主窗口把播放器接进来。接上才连 finished，才能自动下一首。
func attach_player(new_player: AudioStreamPlayer) -> void:
	player = new_player
	player.finished.connect(_on_track_finished)
	player.volume_db = _volume_to_db(_volume)


## 主窗口把落子音效的播放器接进来，这条滑条才有东西可调。
## 传的是数组（落子声有两个播放器轮流用），音量要一起设。
func attach_sfx(new_players: Array[AudioStreamPlayer]) -> void:
	sfx_players = new_players
	for voice: AudioStreamPlayer in sfx_players:
		voice.volume_db = _volume_to_db(_sfx_volume)


## 每次被打开都重扫歌单：往 music/ 里丢的歌不用重启就能看见。
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		reload_playlist()


# --- 歌单 -------------------------------------------------------------------

## 重新扫一遍 music/、重建歌单树，并按路径把正在放的那首找回来。
func reload_playlist() -> void:
	var keep := _current_path
	_error = ""
	_scan_music()
	_index = _find_index(keep)
	_rebuild_tree()
	_reveal_current()
	_refresh_now_playing()
	_refresh_button()


## 扫两个来源，合并成一个歌单：玩家的排在前面、出厂的跟在后面。
## **同名文件夹并成一行**，里面玩家的歌在前、出厂的在后；只在一边有的单独占一行。
## 目录不存在的来源直接跳过（玩家的那份 _ensure_user_dir 会建出来）。
func _scan_music() -> void:
	_folders.clear()
	_root_tracks.clear()
	_tracks.clear()

	var sources: Array[Dictionary] = [
		{"source": SOURCE_USER, "dir": USER_MUSIC_DIR},
		{"source": SOURCE_BUILTIN, "dir": MUSIC_DIR},
	]
	var merged: Dictionary = {}
	for entry: Dictionary in sources:
		var found := _scan_root(str(entry["source"]), str(entry["dir"]))
		_root_tracks.append_array(found["root_tracks"])
		for folder: Dictionary in found["folders"]:
			var name := str(folder["name"])
			if not merged.has(name):
				merged[name] = {"name": name, "tracks": []}
			(merged[name]["tracks"] as Array).append_array(folder["tracks"])

	var names: Array = merged.keys()
	names.sort()
	for name: String in names:
		_folders.append(merged[name])

	# 播放顺序和界面上看到的顺序一致：先顶层散歌，再逐个文件夹
	_tracks.append_array(_root_tracks)
	for folder: Dictionary in _folders:
		_tracks.append_array(folder["tracks"])


## 扫一个根目录，收成 { folders, root_tracks }；目录不存在就返回两样都空。
## folders 里每项是 { name, tracks }（**空文件夹也收**，歌单里要列出来）。
func _scan_root(source: String, root_dir: String) -> Dictionary:
	var dir := DirAccess.open(root_dir)
	if dir == null:
		return {"folders": [], "root_tracks": []}
	var folders: Array[String] = []
	var files: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			if dir.current_is_dir():
				folders.append(entry)
			else:
				var name := _audio_name(entry)
				if not name.is_empty() and not files.has(name):
					files.append(name)
		entry = dir.get_next()
	dir.list_dir_end()
	folders.sort()
	files.sort()

	var root_tracks: Array[Dictionary] = []
	for file: String in files:
		root_tracks.append(_make_track(root_dir, file, source))
	var folder_list: Array[Dictionary] = []
	for folder: String in folders:
		var tracks: Array[Dictionary] = []
		_collect_tracks(root_dir.path_join(folder), tracks, source)
		folder_list.append({"name": folder, "tracks": tracks})
	return {"folders": folder_list, "root_tracks": root_tracks}


## 递归收一个文件夹里的音频。再深一层的子文件夹也算，都归到这个顶层文件夹名下。
## 同一层里文件排在子文件夹前面，都按名字排，所以每次扫出来的顺序都一样。
func _collect_tracks(dir_path: String, out: Array[Dictionary], source: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var folders: Array[String] = []
	var files: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			if dir.current_is_dir():
				folders.append(entry)
			else:
				var name := _audio_name(entry)
				if not name.is_empty() and not files.has(name):
					files.append(name)
		entry = dir.get_next()
	dir.list_dir_end()
	folders.sort()
	files.sort()

	for file: String in files:
		out.append(_make_track(dir_path, file, source))
	for folder: String in folders:
		_collect_tracks(dir_path.path_join(folder), out, source)


## 把 DirAccess 报出来的名字换成资源名；不是音频就返回空串。
##
## 导出成 exe 之后，包里列出来的是 `xxx.mp3.import` 而不是 `xxx.mp3`：真正的音频被
## remap 进了 .godot/imported/，原始路径在包里只剩 .import 这条记录。
## （实测：打包后直接按 mp3 扩展名过滤，24 首一个都收不到，歌单会是空的。）
## 所以先把 .import 剥掉再认；从工程直接跑时两种名字都在，调用方负责去重。
func _audio_name(entry: String) -> String:
	var name := entry.trim_suffix(".import")
	if EXTENSIONS.has(name.get_extension().to_lower()):
		return name
	return ""


## 拼一条歌单记录。where 是鼠标悬停在歌单某行上时显示的说明：来源 + 相对路径。
## source 决定它算「我的音乐」还是「出厂音乐」。
func _make_track(dir_path: String, file: String, source: String) -> Dictionary:
	var full := dir_path.path_join(file)
	var own_root := USER_MUSIC_DIR if source == SOURCE_USER else MUSIC_DIR
	var label := "我的音乐" if source == SOURCE_USER else "出厂音乐"
	return {
		"path": full,
		"title": file.get_basename(),
		"where": "%s · %s" % [label, full.trim_prefix(own_root + "/")],
		"source": source,
	}


## 在歌单里按路径找下标；找不到返回 -1。
func _find_index(path: String) -> int:
	if path.is_empty():
		return -1
	for i: int in _tracks.size():
		if str(_tracks[i]["path"]) == path:
			return i
	return -1


# --- 歌单树 -----------------------------------------------------------------

## 把歌单重建出来。文件夹一行、里面的歌在下一层；空文件夹给一行灰字说明。
## 展开状态记在 _expanded 里，所以重扫（每次开窗口都会重扫）之后不会全缩回去。
func _rebuild_tree() -> void:
	_rebuilding = true
	_item_by_path.clear()
	list.clear()
	var root := list.create_item()

	for track: Dictionary in _root_tracks:
		_add_track_item(root, track)

	for folder: Dictionary in _folders:
		var name := str(folder["name"])
		var tracks: Array = folder["tracks"]
		var item := list.create_item(root)
		item.set_metadata(0, {"folder": name})
		if tracks.is_empty():
			item.set_text(0, "%s（空）" % name)
			var hint := list.create_item(item)
			hint.set_text(0, "这个文件夹里还没有歌")
			hint.set_selectable(0, false)
			hint.set_custom_color(0, _dim(list.get_theme_color("font_color"), 0.45))
		else:
			item.set_text(0, "%s（%d）" % [name, tracks.size()])
			for track: Dictionary in tracks:
				_add_track_item(item, track)
		item.set_collapsed(not bool(_expanded.get(name, false)))

	_rebuilding = false


## 把一个 TreeItem 的文字压暗一点，用来拉开层次（不影响对比度，只降一点点）。
func _dim(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * alpha)


## 往树上挂一首歌：文字是曲名，悬停显示它的来源和路径。
## **出厂的压得更淡**，玩家自己放的和文件夹名一样亮——一眼看得出哪些是后加的。
func _add_track_item(parent: TreeItem, track: Dictionary) -> void:
	var item := list.create_item(parent)
	item.set_text(0, str(track["title"]))
	item.set_tooltip_text(0, str(track["where"]))
	var user_made := str(track.get("source", SOURCE_BUILTIN)) == SOURCE_USER
	item.set_custom_color(0, _dim(list.get_theme_color("font_color"),
		0.82 if user_made else 0.55))
	item.set_metadata(0, {"track": str(track["path"])})
	_item_by_path[str(track["path"])] = item


## 展开并选中正在放的那首——按「下一首」跳到别的文件夹时，
## 不展开的话根本看不到自己在听哪首。
func _reveal_current() -> void:
	var item: TreeItem = _item_by_path.get(_current_path)
	if item == null:
		return
	var parent := item.get_parent()
	if parent != null:
		var meta: Variant = parent.get_metadata(0)
		if meta is Dictionary and meta.has("folder"):
			parent.set_collapsed(false)
			_expanded[str(meta["folder"])] = true
	item.select(0)
	list.scroll_to_item(item)


## 点了歌单里的一行：歌就播放，文件夹就展开 / 收起。
func _on_item_selected() -> void:
	if _rebuilding:
		return
	var item := list.get_selected()
	if item == null:
		return
	var meta: Variant = item.get_metadata(0)
	if not (meta is Dictionary):
		return
	if meta.has("track"):
		play_index(_find_index(str(meta["track"])))
	elif meta.has("folder"):
		var name := str(meta["folder"])
		item.set_collapsed(not item.collapsed)
		_expanded[name] = not item.collapsed


# --- 播放 -------------------------------------------------------------------

## 放第 index 首。
func play_index(index: int) -> void:
	if index < 0 or index >= _tracks.size():
		return
	var track := _tracks[index]
	var stream := _load_stream(str(track["path"]))
	if stream == null:
		_error = "放不了这首：%s" % track["title"]
		_refresh_now_playing()
		return

	_error = ""
	_index = index
	_current_path = str(track["path"])
	_disable_stream_loop(stream)
	player.stream = stream
	player.play()
	_reveal_current()
	progress.set_value_no_signal(0.0)
	_refresh_now_playing()
	_refresh_button()


## 载入一首歌。两条路，这是「实时读取」的关键：
##   1. 先 load() 走 Godot 导入好的资源 —— 这是正规路径，导出成 exe 之后也有效
##   2. 失败了再直接读磁盘上的文件 —— 刚拖进文件夹、Godot 还没来得及导入的歌
##      也能立刻放出来
func _load_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var stream: Resource = load(path)
		if stream is AudioStream:
			return stream
	var absolute := ProjectSettings.globalize_path(path)
	match path.get_extension().to_lower():
		"mp3":
			return AudioStreamMP3.load_from_file(absolute)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(absolute)
		"wav":
			return AudioStreamWAV.load_from_file(absolute)
	return null


## 单曲不要自己循环——循环交给歌单管，否则一首放完不会自动下一首。
func _disable_stream_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop = false


## 播放/暂停。还没选歌时按下去就从第一首开始。
func toggle_pause() -> void:
	if player == null:
		return
	if _index < 0:
		if not _tracks.is_empty():
			play_index(0)
		return
	if _is_playing():
		player.stream_paused = true
	elif player.stream_paused:
		player.stream_paused = false
	else:
		# 已经放完了停在原地，再按就重放这一首
		player.play()
	_refresh_button()


## 下一首；到最后一首回到第一首。
func play_next() -> void:
	if _tracks.is_empty():
		return
	if _index < 0:
		play_index(0)
	else:
		play_index((_index + 1) % _tracks.size())


func _on_track_finished() -> void:
	play_next()


func _is_playing() -> bool:
	return player != null and player.playing and not player.stream_paused


# --- 界面 -------------------------------------------------------------------

## 每帧把播放位置刷到播放条上。用 set_value_no_signal，
## 否则这行赋值会触发 value_changed，被当成用户在拖条。
func _process(_delta: float) -> void:
	if player == null:
		return
	var length := 0.0
	if player.stream != null:
		length = player.stream.get_length()
	if not _dragging:
		progress.max_value = maxf(0.001, length)
		var position := player.get_playback_position() if player.playing or player.stream_paused else 0.0
		progress.set_value_no_signal(clampf(position, 0.0, progress.max_value))
	clock.text = "%s / %s" % [_format_time(progress.value), _format_time(length)]
	_refresh_button()


func _refresh_now_playing() -> void:
	if not _error.is_empty():
		now_playing.text = _error
	elif _tracks.is_empty():
		now_playing.text = EMPTY_HINT
	elif _index < 0 or _index >= _tracks.size():
		now_playing.text = "从下面的歌单里选一首"
	else:
		now_playing.text = str(_tracks[_index]["title"])


func _refresh_button() -> void:
	var text := "暂停" if _is_playing() else "播放"
	if play_pause_button.text != text:
		play_pause_button.text = text


func _on_close_requested() -> void:
	# 只隐藏，不停止播放：音乐是背景音，关掉窗口不该把它掐了
	hide()
	closed.emit()


func _on_progress_changed(value: float) -> void:
	# 拖的过程中不定位，等松手一次性 seek，否则每动一下都重新寻址，一顿一顿的
	if _dragging or player == null:
		return
	player.seek(value)


func _on_progress_drag_started() -> void:
	_dragging = true


func _on_progress_drag_ended(value_changed: bool) -> void:
	_dragging = false
	if value_changed and player != null:
		player.seek(progress.value)


func _on_volume_changed(value: float) -> void:
	_volume = clampf(value, 0.0, 1.0)
	if player != null:
		player.volume_db = _volume_to_db(_volume)


## 音效那条滑条。音效和音乐各走各的播放器，所以拉到底只静音一边。
func _on_sfx_volume_changed(value: float) -> void:
	_sfx_volume = clampf(value, 0.0, 1.0)
	for voice: AudioStreamPlayer in sfx_players:
		voice.volume_db = _volume_to_db(_sfx_volume)


## 0 会被 linear_to_db 变成负无穷，垫一个极小的下限。
func _volume_to_db(value: float) -> float:
	return linear_to_db(maxf(value, 0.0001))


func _format_time(seconds: float) -> String:
	if not is_finite(seconds) or seconds < 0.0:
		seconds = 0.0
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]
