extends Window

## 设置窗口：独立小窗口，放先手选择、对手棋力的两个开关、禁手规则和四处配色。
## 和另外几个窗口一样：点自己的关闭按钮只是隐藏，主窗口能再打开它。
## 任何改动都立刻生效并立刻写盘，所以这里没有「保存」按钮。
##
## 注意：这里故意不把子窗口内嵌（`gui_embed_subwindows` 保持默认的 false）。
## 取色器展开后有两百多像素宽、四百像素高，内嵌进这个小窗口会被裁掉，看起来就像点不动。

## 被单独关掉时发出；主窗口据此把「设置」按钮恢复成可点。
signal closed
## 用户改了开关或颜色时发出，参数是当前完整的设置对象，主窗口据此立刻应用并写盘。
signal settings_changed(settings: GameSettings)

@onready var player_first_check: CheckButton = $Column/PlayerFirst
@onready var position_eval_check: CheckButton = $Column/PositionEval
@onready var search_check: CheckButton = $Column/TwoPlySearch
@onready var forbidden_check: CheckButton = $Column/Forbidden
@onready var board_color_picker: ColorPickerButton = $Column/Colors/BoardColor
@onready var line_color_picker: ColorPickerButton = $Column/Colors/LineColor
@onready var background_color_picker: ColorPickerButton = $Column/Colors/BackgroundColor
@onready var ui_color_picker: ColorPickerButton = $Column/Colors/UIColor
@onready var reset_button: Button = $Column/Reset

## 当前设置对象，由主窗口在打开时传进来。
var settings: GameSettings = GameSettings.new()
## 程序改界面时置位，用来屏蔽信号，免得把「同步」当成「用户改动」。
var _syncing: bool = false


## 接好信号。
func _ready() -> void:
	close_requested.connect(_on_close_requested)
	player_first_check.toggled.connect(_on_toggle_changed)
	position_eval_check.toggled.connect(_on_toggle_changed)
	search_check.toggled.connect(_on_toggle_changed)
	forbidden_check.toggled.connect(_on_toggle_changed)
	board_color_picker.color_changed.connect(_on_color_changed)
	line_color_picker.color_changed.connect(_on_color_changed)
	background_color_picker.color_changed.connect(_on_color_changed)
	ui_color_picker.color_changed.connect(_on_color_changed)
	reset_button.pressed.connect(_on_reset_pressed)


## 把设置对象刷到界面上（全程屏蔽信号，不会误报「用户改了」）。
func show_settings(current: GameSettings) -> void:
	settings = current
	_syncing = true
	player_first_check.button_pressed = settings.player_goes_first
	position_eval_check.button_pressed = settings.use_position_eval
	search_check.button_pressed = settings.use_search
	forbidden_check.button_pressed = settings.use_forbidden
	board_color_picker.color = settings.board_color
	line_color_picker.color = settings.line_color
	background_color_picker.color = settings.background_color
	ui_color_picker.color = settings.ui_color
	_syncing = false


## 关闭按钮回调：隐藏窗口并通知主窗口。
func _on_close_requested() -> void:
	hide()
	closed.emit()


## 开关变化：这里只补一条依赖——两层搜索离不开局面评估。
func _on_toggle_changed(_pressed: bool) -> void:
	if _syncing:
		return
	settings.player_goes_first = player_first_check.button_pressed
	settings.use_position_eval = position_eval_check.button_pressed
	settings.use_search = search_check.button_pressed
	settings.use_forbidden = forbidden_check.button_pressed
	if settings.use_search and not settings.use_position_eval:
		settings.use_position_eval = true
		_syncing = true
		position_eval_check.button_pressed = true
		_syncing = false
	settings_changed.emit(settings)


## 颜色变化：四个取色器共用这个回调。
func _on_color_changed(_color: Color) -> void:
	if _syncing:
		return
	settings.board_color = board_color_picker.color
	settings.line_color = line_color_picker.color
	settings.background_color = background_color_picker.color
	settings.ui_color = ui_color_picker.color
	settings_changed.emit(settings)


## 恢复默认：把开关和配色都退回默认值，刷回界面并通知主窗口。
func _on_reset_pressed() -> void:
	settings.reset_to_defaults()
	show_settings(settings)
	settings_changed.emit(settings)
