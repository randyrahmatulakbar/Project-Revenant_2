extends CanvasLayer

const MAIN_MENU_SCENE = "res://main menu/mainmenu.tscn"

# Referensi tombol pause utama
@onready var resume_button = $PanelControl/ColorRect/MenuContainer/ResumeButton
@onready var settings_button = $PanelControl/ColorRect/MenuContainer/SettingsButton
@onready var main_menu_button = $PanelControl/ColorRect/MenuContainer/MainMenuButton
@onready var exit_button = $PanelControl/ColorRect/MenuContainer/ExitButton

# Container Utama vs Panel Settings
@onready var menu_container = $PanelControl/ColorRect/MenuContainer
@onready var settings_panel = $Panel
@onready var back_button = $Panel/MarginContainer/VBoxContainer/BackButton

# Node Kontrol Settings
@onready var master_slider = $Panel/MarginContainer/VBoxContainer/HBoxContainer/MasterSlider
@onready var sens_slider = $Panel/MarginContainer/VBoxContainer/HBoxContainer2/SensSlider
@onready var fullscreen_checkbox = $Panel/MarginContainer/VBoxContainer/HBoxContainer3/FullscreenCheckBox

func _ready():
	# Reset status pause saat game baru mulai
	get_tree().paused = false
	hide()
	
	if menu_container:
		menu_container.show()
	if settings_panel:
		settings_panel.hide()
	
	# Connect tombol pause utama
	resume_button.pressed.connect(_on_resume_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	
	# Connect tombol back
	back_button.pressed.connect(_on_back_pressed)
	
	# --- CONNECT KONTROL SETTINGS ---
	_init_settings_values()
	
	master_slider.value_changed.connect(_on_master_slider_value_changed)
	sens_slider.value_changed.connect(_on_sens_slider_value_changed)
	fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)

func _init_settings_values():
	# Master Volume (0.0 sampai 1.0)
	master_slider.min_value = 0.0001
	master_slider.max_value = 1.0
	master_slider.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	
	# Fullscreen Checkbox Status
	var mode = DisplayServer.window_get_mode()
	fullscreen_checkbox.button_pressed = (mode == DisplayServer.WINDOW_MODE_FULLSCREEN)

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		if settings_panel and settings_panel.visible:
			_close_settings()
		else:
			toggle_pause()

func toggle_pause():
	var is_paused = !get_tree().paused
	get_tree().paused = is_paused
	
	# Tampilkan/sembunyikan Pause Menu
	visible = is_paused
	
	# Sembunyikan/tampilkan Crosshair
	var crosshair = get_tree().root.find_child("crosshair", true, false)
	if crosshair:
		crosshair.visible = !is_paused

	# Sembunyikan/tampilkan HUD pas pause
	var hud = get_tree().root.find_child("HUD", true, false)
	if hud:
		hud.visible = !is_paused

	if is_paused:
		# Saat pause dipicu, paksa menu utama tampil & settings sembunyi
		if menu_container:
			menu_container.show()
		if settings_panel:
			settings_panel.hide()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# --- LOGIKA BUKA / TUTUP SETTINGS ---

func _on_settings_pressed():
	if menu_container:
		menu_container.hide()
	if settings_panel:
		settings_panel.show()

func _on_back_pressed():
	_close_settings()

func _close_settings():
	if settings_panel:
		settings_panel.hide()
	if menu_container:
		menu_container.show()

# --- LOGIKA SETTINGS ---

func _on_master_slider_value_changed(value: float):
	AudioServer.set_bus_volume_db(0, linear_to_db(value))

func _on_sens_slider_value_changed(value: float):
	# Cari node Player dan ubah sensitivitasnya
	var player = get_tree().root.find_child("Player", true, false)
	if player:
		if "SENSITIVITY" in player:
			player.SENSITIVITY = value
		elif "mouse_sensitivity" in player:
			player.mouse_sensitivity = value

func _on_fullscreen_toggled(toggled_on: bool):
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

# --- LOGIKA TOMBOL UTAMA ---

func _on_resume_pressed():
	toggle_pause()

func _on_main_menu_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _on_exit_pressed():
	get_tree().quit()
