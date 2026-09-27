extends Window

## 设置窗口：独立小窗口，放电脑棋力的三个开关、三处配色和一个「恢复默认」。
## 和另外两个窗口一样：点自己的关闭按钮只是隐藏，主窗口能再打开它。
## 任何改动都立刻生效并立刻写盘，所以这里没有「保存」按钮。

## 被单独关掉时发出；主窗口据此把「设置」按钮恢复成可点。
signal closed
## 用户改了开关或颜色时发出，参数是当前完整的设置对象，主窗口据此立刻应用并写盘。
signal settings_changed(settings: GameSettings)

@onready var position_eval_check: CheckButton = $Column/AI/PositionEval
@onready var search_check: CheckButton = $Column/AI/TwoPlySearch
@onready var forbidden_check: CheckButton = $Column/AI/Forbidden
@onready var board_color_picker: ColorPickerButton = $Column/Colors/BoardColor
@onready var line_color_picker: ColorPickerButton = $Column/Colors/LineColor
@onready var background_color_picker: ColorPickerButton = $Column/Colors/BackgroundColor
@onready var timing_label: Label = $Column/Footer/Timing
@onready var reset_button: Button = $Column/Footer/Reset

## 当前设置对象，由主窗口在打开时传进来。
var settings: GameSettings = GameSettings.new()
## 程序改界面时置位，用来屏蔽信号，免得把「同步」当成「用户改动」。
var _syncing: bool = false


## 接好信号；颜色选择框内嵌在本窗口里显示，不然会再蹦出一个系统窗口。
func _ready() -> void:
	gui_embed_subwindows = true
	close_requested.connect(_on_close_requested)
	position_eval_check.toggled.connect(_on_toggle_changed)
	search_check.toggled.connect(_on_toggle_changed)
	forbidden_check.toggled.connect(_on_toggle_changed)
	board_color_picker.color_changed.connect(_on_color_changed)
	line_color_picker.color_changed.connect(_on_color_changed)
	background_color_picker.color_changed.connect(_on_color_changed)
	reset_button.pressed.connect(_on_reset_pressed)


## 把设置对象刷到界面上（全程屏蔽信号，不会误报「用户改了」）。
func show_settings(current: GameSettings) -> void:
	settings = current
	_syncing = true
	position_eval_check.button_pressed = settings.use_position_eval
	search_check.button_pressed = settings.use_search
	forbidden_check.button_pressed = settings.use_forbidden
	board_color_picker.color = settings.board_color
	line_color_picker.color = settings.line_color
	background_color_picker.color = settings.background_color
	_syncing = false


## 显示上一手电脑算了多久；0 表示还没算过。
func set_timing(milliseconds: int) -> void:
	if milliseconds <= 0:
		timing_label.text = "上一手电脑耗时：—"
	else:
		timing_label.text = "上一手电脑耗时：%d ms" % milliseconds


## 关闭按钮回调：隐藏窗口并通知主窗口。
func _on_close_requested() -> void:
	hide()
	closed.emit()


## 开关变化：两个「需要局面评估」的依赖在这里补上。
func _on_toggle_changed(_pressed: bool) -> void:
	if _syncing:
		return
	settings.use_position_eval = position_eval_check.button_pressed
	settings.use_search = search_check.button_pressed
	settings.use_forbidden = forbidden_check.button_pressed
	if settings.use_search and not settings.use_position_eval:
		settings.use_position_eval = true
		_syncing = true
		position_eval_check.button_pressed = true
		_syncing = false
	settings_changed.emit(settings)


## 颜色变化：三个取色器共用这个回调。
func _on_color_changed(_color: Color) -> void:
	if _syncing:
		return
	settings.board_color = board_color_picker.color
	settings.line_color = line_color_picker.color
	settings.background_color = background_color_picker.color
	settings_changed.emit(settings)


## 恢复默认：把开关和配色都退回默认值，刷回界面并通知主窗口。
func _on_reset_pressed() -> void:
	settings.reset_to_defaults()
	show_settings(settings)
	settings_changed.emit(settings)
