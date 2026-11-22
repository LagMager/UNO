class_name SettingsPanel
extends RefCounted

## The game's settings (volume, window mode), saved in user://settings.cfg and applied at
## startup. They are changed in the main menu's room (the bottle and the window shutters).

const PATH := "user://settings.cfg"


## Reads the saved settings and applies them (called once when the game starts).
static func apply_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	_apply(float(cfg.get_value("audio", "volume", 0.8)), bool(cfg.get_value("video", "fullscreen", false)))


static func _apply(volume: float, fullscreen: bool) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.001)
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
