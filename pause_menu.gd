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

var _crosshair_was_visible := true
var _hud_was_visible := true
var _pause_buttons: Array = []

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
	_style_pause()
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
		if is_paused:
			_crosshair_was_visible = crosshair.visible
			crosshair.visible = false
		else:
			crosshair.visible = _crosshair_was_visible

	var hud = get_tree().root.find_child("HUD", true, false)
	if hud:
		if is_paused:
			_hud_was_visible = hud.visible
			hud.visible = false
		else:
			hud.visible = _hud_was_visible

	if is_paused:
		menu_container.show()
		settings_menu.hide()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		HudSkin.play_in(_pause_buttons, 0.1)
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
	HudSkin.play_in(_pause_buttons)


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
			
func _style_pause() -> void:
	HudSkin.style_settings(settings_menu)
	_pause_buttons = [resume_button, restart_button, settings_button, main_menu_button, exit_button]
	for b in _pause_buttons:
		HudSkin.skin_button(b, Vector2(360, 50), 24)

	# layout rata kiri, sama seperti main menu
	menu_container.set_anchors_preset(Control.PRESET_CENTER_LEFT, true)
	menu_container.grow_horizontal = Control.GROW_DIRECTION_END
	menu_container.grow_vertical = Control.GROW_DIRECTION_BOTH
	menu_container.offset_left = 72
	menu_container.offset_right = 72 + 360
	menu_container.offset_top = -200
	menu_container.offset_bottom = 200
	menu_container.add_theme_constant_override("separation", 10)
	$PanelControl/ColorRect/MenuContainer/TitleLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	HudSkin.make_shade($PanelControl/ColorRect)
