extends Control

@onready var master_slider = $CenterContainer/PanelContainer/VBoxContainer/AudioSection/MasterVolume/Slider
@onready var music_slider = $CenterContainer/PanelContainer/VBoxContainer/AudioSection/MusicVolume/Slider
@onready var sfx_slider = $CenterContainer/PanelContainer/VBoxContainer/AudioSection/SFXVolume/Slider
@onready var fullscreen_check = $CenterContainer/PanelContainer/VBoxContainer/VideoSection/FullscreenCheck
@onready var vsync_check = $CenterContainer/PanelContainer/VBoxContainer/VideoSection/VSyncCheck

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_settings()
	await get_tree().process_frame
	$CenterContainer/PanelContainer/VBoxContainer/BackBtn.grab_focus()

func _load_settings():
	master_slider.value = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")) if AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")) > -60 else 0.0
	music_slider.value = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) if AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) > -60 else 0.0
	sfx_slider.value = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")) if AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")) > -60 else 0.0
	
	fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	vsync_check.button_pressed = DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_ENABLED

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_master_volume_changed(value: float):
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))

func _on_music_volume_changed(value: float):
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(value))

func _on_sfx_volume_changed(value: float):
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(value))

func _on_fullscreen_toggled(toggled_on: bool):
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_vsync_toggled(toggled_on: bool):
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if toggled_on else DisplayServer.VSYNC_DISABLED)