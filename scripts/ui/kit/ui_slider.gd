class_name UiSlider
extends HSlider

## Slider bound to a Settings value. Saves when you let go or move on.

var key: String


func _init(settings_key := "", lo := 0.0, hi := 1.0) -> void:
	key = settings_key
	theme_type_variation = "RowSlider"
	min_value = lo
	max_value = hi
	step = 0.05
	custom_minimum_size = Vector2(260, 32)
	focus_mode = Control.FOCUS_ALL
	if key != "":
		value = Settings.get_value(key)
	value_changed.connect(_on_value)
	drag_ended.connect(func(_c): Settings.save_settings())
	focus_exited.connect(Settings.save_settings)
	focus_entered.connect(func(): Sfx.play("ui_move"))


func _on_value(v: float) -> void:
	if key == "":
		return
	Settings.set_value(key, v, false)
	if key == "sfx_volume" or key == "master_volume":
		Sfx.play("ui_move")
