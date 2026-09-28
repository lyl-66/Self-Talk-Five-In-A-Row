class_name ConfigStore
extends RefCounted

## 三套存档（比分、设置、窗口布局）共用的读写零件。
##
## 写盘一律「先落 .tmp 再整文件替换」，避免写一半断电把存档写花；
## 读盘一律容错，字段缺失或类型不对就回落到调用方给的默认值，绝不让游戏崩。
##
## 取值不直接用 int() / bool() 之类的一元构造器：Godot 的 bool() 只认
## bool / int / float，碰上被手改成 "true" 这种带引号的字符串会直接报错，
## 而且会把整个读盘过程打断——比回落到默认值糟得多。


## 把 config 写进 path；任一步失败都只报警告，不抛错。
static func save_atomic(config: ConfigFile, path: String) -> void:
	var temp_path := path + ".tmp"
	if config.save(temp_path) != OK:
		push_warning("存档写入失败：%s" % temp_path)
		return
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path),
			ProjectSettings.globalize_path(path)) != OK:
		push_warning("存档替换失败：%s" % path)


## 读一个布尔项；缺失或类型不对就用默认值。
static func pick_bool(config: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var value: Variant = config.get_value(section, key, fallback)
	if value is bool:
		return value
	if value is int:
		return value != 0
	if value is float:
		return not is_zero_approx(value)
	return fallback


## 读一个整数项；缺失、类型不对或负数都当作 0。
static func pick_int(config: ConfigFile, section: String, key: String, fallback: int = 0) -> int:
	var value: Variant = config.get_value(section, key, fallback)
	if value is int:
		return maxi(0, value)
	if value is float:
		return maxi(0, int(value))
	if value is String:
		return maxi(0, int(value))
	return maxi(0, fallback)


## 读一个颜色项；缺失或类型不对就用默认值。
static func pick_color(config: ConfigFile, section: String, key: String, fallback: Color) -> Color:
	var value: Variant = config.get_value(section, key, fallback)
	return value if value is Color else fallback


## 读一个整数数组项（比如话题洗牌袋）；缺失或类型不对就返回 fallback。
## 数组里混进来的非整数元素直接丢掉，不整份作废。
##
## 默认值给的是空数组而不是 null：ConfigFile.get_value 传 null 会被当成
## 「没给默认值」，读不到时直接报错（window_layout.gd 里也踩过同一个坑）。
static func pick_int_array(config: ConfigFile, section: String, key: String,
		fallback: Array[int]) -> Array[int]:
	var value: Variant = config.get_value(section, key, [])
	if not (value is Array):
		return fallback
	var out: Array[int] = []
	for item: Variant in value:
		if item is int:
			out.append(item)
		elif item is float:
			out.append(int(item))
	if out.is_empty():
		return fallback
	return out
