extends CanvasLayer

const MAIN_MENU_SCENE = "res://main menu/mainmenu.tscn"

# Tombol pause
@onready var resume_button = $PanelControl/ColorRect/MenuContainer/ResumeButton
@onready var restart_button = $PanelControl/ColorRect/MenuContainer/Restart
@onready var settings_button = $PanelControl/ColorRect/MenuContainer/SettingsButton
@onready var main_menu_button = $PanelControl/ColorRect/MenuContainer/MainMenuButton
@onready var exit_button = $PanelControl/ColorRect/MenuContainer/ExitButton

# Container menu & settings (scene baru)
@onready var menu_container = $PanelControl/ColorRect/MenuContainer
@onready var settings_menu = $SettingsMenu


func _ready():
	get_tree().paused = false
	hide()

	menu_container.show()
	settings_menu.hide()

	resume_button.pressed.connect(_on_resume_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

	settings_menu.back_pressed.connect(_close_settings)
	settings_menu.sensitivity_changed.connect(_apply_sensitivity)

	# Terapkan setting tersimpan saat level dimulai
	SettingsMenu.apply_saved()
	_apply_sensitivity.call_deferred(SettingsMenu.get_sensitivity())


func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		if settings_menu.visible:
			_close_settings()
		else:
			toggle_pause()


func toggle_pause():
	var is_paused = !get_tree().paused
	get_tree().paused = is_paused
	visible = is_paused

	var crosshair = get_tree().root.find_child("crosshair", true, false)
	if crosshair:
		crosshair.visible = !is_paused

	var hud = get_tree().root.find_child("HUD", true, false)
	if hud:
		hud.visible = !is_paused

	if is_paused:
		menu_container.show()
		settings_menu.hide()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Tombol ---
func _on_resume_pressed():
	toggle_pause()


func _on_restart_pressed():
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_settings_pressed():
	menu_container.hide()
	settings_menu.show()


func _close_settings():
	settings_menu.hide()
	menu_container.show()


func _on_main_menu_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_exit_pressed():
	get_tree().quit()


# --- Sensitivitas ---
# Slider adalah pengali (default 1.0) dari nilai bawaan player,
# jadi nilai asli di script player tetap jadi acuan.
func _apply_sensitivity(multiplier: float):
	var player = get_tree().root.find_child("Player", true, false)
	if not player:
		return
	for prop in ["SENSITIVITY", "mouse_sensitivity"]:
		if prop in player:
			var meta_key = "base_" + prop
			if not player.has_meta(meta_key):
				player.set_meta(meta_key, player.get(prop))
			player.set(prop, player.get_meta(meta_key) * multiplier)
			return
