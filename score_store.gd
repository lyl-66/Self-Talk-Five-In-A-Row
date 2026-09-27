class_name ScoreStore
extends RefCounted

## 比分存档。总分写在 user://score.cfg，每局明细一行一局追加到 user://history.jsonl。
## 在 Windows 上这两个文件落在 %APPDATA%\Godot\app_userdata\<项目名>\ 下，
## 跟着用户账号走，不随游戏更新或重新下载丢失。
## 读取一律容错：文件缺失、被手改坏、字段类型不对，都当作从零开始，绝不让游戏崩。

## 总分文件。
const SCORE_PATH: String = "user://score.cfg"
## 每局明细文件，JSON Lines：一行一个 JSON 对象。
const HISTORY_PATH: String = "user://history.jsonl"
## 读「最近一局」时只取文件末尾这么多字节，避免记录变长后整文件读一遍。
const TAIL_BYTES: int = 2048

## 累计总比分，跨局保留。
var player_wins: int = 0
var ai_wins: int = 0
var draw_count: int = 0
## 已经记录过多少局。
var games_played: int = 0


## 从磁盘读回总比分；文件不存在或读不出来就保持从零开始。
func load_from_disk() -> void:
	player_wins = 0
	ai_wins = 0
	draw_count = 0
	games_played = 0
	var config := ConfigFile.new()
	if config.load(SCORE_PATH) != OK:
		return
	player_wins = ConfigStore.pick_int(config, "total", "player_wins")
	ai_wins = ConfigStore.pick_int(config, "total", "ai_wins")
	draw_count = ConfigStore.pick_int(config, "total", "draws")
	games_played = ConfigStore.pick_int(config, "total", "games")


## 把总分写回磁盘。写法和容错都在 ConfigStore 里。
func save_totals() -> void:
	var config := ConfigFile.new()
	config.set_value("total", "player_wins", player_wins)
	config.set_value("total", "ai_wins", ai_wins)
	config.set_value("total", "draws", draw_count)
	config.set_value("total", "games", games_played)
	ConfigStore.save_atomic(config, SCORE_PATH)


## 追加一局明细并让局数加一；result 取 player / ai / draw。
## 局数在明细真的写进去之后才加：写失败时窗口上的「已保存 N 局」
## 不能比明细多出一条。
func append_game(result: String, moves: int) -> void:
	# READ_WRITE 不会创建文件，首次要靠 WRITE 建出来
	var file := FileAccess.open(HISTORY_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(HISTORY_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("对局明细写入失败：%s（错误码 %d）" % [HISTORY_PATH, FileAccess.get_open_error()])
		return
	file.seek_end()
	file.store_line(JSON.stringify({
		"time": Time.get_datetime_string_from_system(),
		"result": result,
		"moves": moves,
	}))
	file.close()
	games_played += 1


## 取最近一局的明细，用来在窗口上显示一行摘要；没有记录时返回空字典。
func last_game() -> Dictionary:
	var file := FileAccess.open(HISTORY_PATH, FileAccess.READ)
	if file == null:
		return {}
	var size := file.get_length()
	var start := maxi(0, size - TAIL_BYTES)
	file.seek(start)
	var tail := file.get_buffer(size - start).get_string_from_utf8()
	file.close()
	var lines := tail.strip_edges().split("\n", false)
	if lines.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(lines[lines.size() - 1])
	return parsed if parsed is Dictionary else {}


## 清空比分：总分归零，旧的明细改名留档，而不是直接删掉。
func clear() -> void:
	player_wins = 0
	ai_wins = 0
	draw_count = 0
	games_played = 0
	save_totals()
	if not FileAccess.file_exists(HISTORY_PATH):
		return
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(HISTORY_PATH),
			ProjectSettings.globalize_path("user://history-%s.jsonl" % stamp)) != OK:
		push_warning("旧明细归档失败：%s" % HISTORY_PATH)
