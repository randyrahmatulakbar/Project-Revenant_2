extends Control

# Refrensi Node Utama
@onready var vbox_container: VBoxContainer = $VBoxContainer
@onready var options: Panel = $Options
@onready var credit_panel: Panel = $CreditPanel

# Variable global sensitivitas mouse (bisa dipanggil script Player)
static var mouse_sensitivity: float = 1.0

func _ready() -> void:
	# Memastikan panel Settings dan Credit tertutup saat Main Menu dibuka
	if options:
		options.visible = false
	if credit_panel:
		credit_panel.visible = false

# ==========================================
# FUNGSI TOMBOL MENU UTAMA
# ==========================================

func _on_play_pressed() -> void:
	print("Play pressed - berpindah ke game...")
	get_tree().change_scene_to_file("res://main_level.tscn")

func _on_settings_pressed() -> void:
	print("Settings pressed")
	vbox_container.visible = false
	options.visible = true

func _on_credit_pressed() -> void:
	print("Credit pressed")
	vbox_container.visible = false
	credit_panel.visible = true

func _on_exit_pressed() -> void:
	print("Exit pressed")
	get_tree().quit()

# ==========================================
# FUNGSI TOMBOL BACK (KEMBALI)
# ==========================================

# Tombol Back di dalam Panel Settings
func _on_back_pressed() -> void:
	vbox_container.visible = true
	options.visible = false

# Fungsi tambahan (jika nama sinyal tombol back di inspector tertulis _on_back_button_pressed)
func _on_back_button_pressed() -> void:
	_on_back_pressed()

# Tombol Back di dalam Panel Credit
func _on_back_credit_pressed() -> void:
	vbox_container.visible = true
	credit_panel.visible = false

# ==========================================
# FUNGSI FITUR SETTINGS
# ==========================================

# 1. Mengubah Master Volume Suara Game
func _on_master_slider_value_changed(value: float) -> void:
	var bus_index = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))

# 2. Mengubah Sensitivitas Mouse
func _on_sens_slider_value_changed(value: float) -> void:
	mouse_sensitivity = value
	print("Mouse Sensitivity diubah ke: ", mouse_sensitivity)

# 3. Mengubah Layar Fullscreen / Windowed
func _on_fullscreen_check_box_toggled(toggled_on: bool) -> void:
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _on_back_button_credit_pressed() -> void:
	vbox_container.visible = true
	credit_panel.visible = false
