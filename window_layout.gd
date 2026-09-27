class_name WindowLayout
extends RefCounted

## 窗口布局存档：记住每个窗口上次的位置和大小，下次打开回到原处。
## 存在 user://windows.cfg（和比分存档同一个目录），写入同样是先落 .tmp 再替换。
## 读取一律容错：文件缺失、被改坏、字段类型不对，都当作没有记录，回到默认摆放。

## 存档格式版本。改动窗口设计（比如统一尺寸）时把它加一：
## 版本对不上的旧记录会被忽略一次，窗口回到新的默认摆放，之后重新记录。
const VERSION: int = 2
## 布局文件路径。
const PATH: String = "user://windows.cfg"


## 一次性读回所有窗口的布局，返回 { 名字: {position, size, visible} }；没有记录时返回空字典。
static func load_all() -> Dictionary:
	var layout := {}
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return layout
	# 版本对不上说明窗口设计改过了，旧的位置和尺寸不要再用
	if int(config.get_value("meta", "version", 0)) != VERSION:
		return layout
	for key: String in config.get_sections():
		if key == "meta":
			continue
		# 默认值给空字符串而不是 null：传 null 会被 Godot 当成「没给默认值」并报错
		var position: Variant = config.get_value(key, "position", "")
		var size: Variant = config.get_value(key, "size", "")
		var opened: Variant = config.get_value(key, "visible", true)
		if position is Vector2i and size is Vector2i:
			layout[key] = {"position": position, "size": size, "visible": bool(opened)}
	return layout


## 把若干个窗口当前的位置、尺寸和开关状态写进布局文件；字典的键就是窗口的存档名。
static func save_all(windows: Dictionary) -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "version", VERSION)
	for key: String in windows:
		var window: Window = windows[key]
		if window == null:
			continue
		config.set_value(key, "position", window.position)
		config.set_value(key, "size", window.size)
		config.set_value(key, "visible", window.visible)
	var temp_path := PATH + ".tmp"
	if config.save(temp_path) != OK:
		push_warning("窗口布局写入失败：%s" % temp_path)
		return
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path),
			ProjectSettings.globalize_path(PATH)) != OK:
		push_warning("窗口布局替换失败：%s" % PATH)
