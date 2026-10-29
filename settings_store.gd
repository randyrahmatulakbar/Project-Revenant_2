extends RefCounted
# Menerapkan setting yang tersimpan (user://settings.cfg, file yang sama dengan settings_menu.gd) saat menu dibuka.
# Bukan autoload. Taruh satu folder dengan menu_controller.gd.

const PATH := "user://settings.cfg"
const FPS_OPTIONS := [0, 30, 60, 90, 120, 144, 165, 240]


static func apply_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	_bus("Master", float(cfg.get_value("audio", "master", 1.0)))
	_bus("Music", float(cfg.get_value("audio", "music", 1.0)))
	_bus("SFX", float(cfg.get_value("audio", "sfx", 1.0)))
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(cfg.get_value("video", "fullscreen", false)) else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(cfg.get_value("video", "vsync", true)) else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(cfg.get_value("video", "max_fps", 0))
	Engine.set_meta("mouse_sensitivity", float(cfg.get_value("controls", "sensitivity", 1.0)))
	Engine.set_meta("sprint_toggle", bool(cfg.get_value("controls", "sprint_toggle", false)))
	Engine.set_meta("fov", float(cfg.get_value("gameplay", "fov", 75.0)))
	Engine.set_meta("camera_tilt", bool(cfg.get_value("gameplay", "camera_tilt", true)))
	Engine.set_meta("head_bob", bool(cfg.get_value("gameplay", "head_bob", true)))
	Engine.set_meta("brightness", float(cfg.get_value("video", "brightness", 1.0)))
	Engine.set_meta("mute_unfocused", bool(cfg.get_value("audio", "mute_unfocused", false)))


static func _bus(bus_name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i == -1:
		return
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))
