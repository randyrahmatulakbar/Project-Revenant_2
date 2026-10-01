extends Control

# Refrensi Node Utama
@onready var vbox_container: VBoxContainer = $VBoxContainer
@onready var options: Panel = $Options
@onready var credit_panel: Panel = $CreditPanel

# Refrensi Node Credit Baru (Melewati CreditViewport)
@onready var credit_viewport: Control = $CreditPanel/CreditViewport
@onready var credits_label: VBoxContainer = $CreditPanel/CreditViewport/MarginContainer/VBoxContainer

# Konfigurasi Scroll Credits
@export var scroll_speed: float = 40.0  # Kecepatan jalan teks ke atas
var is_credits_active: bool = false
var initial_label_y: float = 0.0

# Variable global sensitivitas mouse
static var mouse_sensitivity: float = 1.0

func _ready() -> void:
	if options:
		options.visible = false
	if credit_panel:
		credit_panel.visible = false
		
	if credits_label:
		initial_label_y = credits_label.position.y

func _process(delta: float) -> void:
	if is_credits_active and credits_label:
		# Geser teks ke atas
		credits_label.position.y -= scroll_speed * delta
		
		# Jika teks sudah habis melewati batas atas CreditViewport, kembali ke menu utama
		if credits_label.position.y < -credits_label.size.y:
			_close_credit()

func _unhandled_input(event: InputEvent) -> void:
	if is_credits_active:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
			_close_credit()

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
	is_credits_active = true
	
	# Posisikan awal teks mulai berjalan dari bagian bawah CreditViewport
	if credits_label and credit_viewport:
		credits_label.position.y = credit_viewport.size.y

func _on_exit_pressed() -> void:
	print("Exit pressed")
	get_tree().quit()

# ==========================================
# FUNGSI TOMBOL BACK (KEMBALI)
# ==========================================

func _on_back_pressed() -> void:
	vbox_container.visible = true
	options.visible = false

func _on_back_button_pressed() -> void:
	_on_back_pressed()

func _on_back_credit_pressed() -> void:
	_close_credit()

func _on_back_button_credit_pressed() -> void:
	_close_credit()

func _close_credit() -> void:
	is_credits_active = false
	vbox_container.visible = true
	credit_panel.visible = false
	if credits_label:
		credits_label.position.y = initial_label_y

# ==========================================
# FUNGSI FITUR SETTINGS
# ==========================================

func _on_master_slider_value_changed(value: float) -> void:
	var bus_index = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))

func _on_sens_slider_value_changed(value: float) -> void:
	mouse_sensitivity = value
	print("Mouse Sensitivity diubah ke: ", mouse_sensitivity)

func _on_fullscreen_check_box_toggled(toggled_on: bool) -> void:
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _input(event: InputEvent) -> void:
	# Jika panel credits sedang aktif dan ada input dari player (klik mouse atau tekan keyboard)
	if is_credits_active and event.is_pressed():
		# Pastikan bukan sekadar gerakan mouse biasa
		if event is InputEventMouseButton or event is InputEventKey:
			_close_credit()
