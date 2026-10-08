extends Control

# Referensi Node Utama
@onready var vbox_container: VBoxContainer = $VBoxContainer
@onready var settings_menu: Control = $SettingsMenu
@onready var credit_panel: Panel = $CreditPanel

# Judul
@onready var title_1: Control = $Background/Label
@onready var title_2: Control = $Background/Label2

# Referensi Node Credit
@onready var credit_viewport: Control = $CreditPanel/CreditViewport
@onready var credits_label: VBoxContainer = $CreditPanel/CreditViewport/MarginContainer/VBoxContainer

# Scroll manual
@export var credit_scroll_speed: float = 100.0

var is_credits_active: bool = false
var initial_label_y: float = 0.0

static var mouse_sensitivity: float = 1.0


func _ready() -> void:
	SettingsMenu.apply_saved()
	mouse_sensitivity = SettingsMenu.get_sensitivity()

	settings_menu.visible = false
	credit_panel.visible = false

	settings_menu.back_pressed.connect(_on_back_pressed)
	settings_menu.sensitivity_changed.connect(_on_sensitivity_changed)

	if credits_label:
		initial_label_y = credits_label.position.y


func _process(delta: float) -> void:
	if not is_credits_active or not credits_label:
		return

	# W / Arrow Up = scroll ke atas
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		credits_label.position.y += credit_scroll_speed * delta

	# S / Arrow Down = scroll ke bawah
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		credits_label.position.y -= credit_scroll_speed * delta


# ==========================================
# INPUT
# ==========================================

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (settings_menu.visible or credit_panel.visible):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


# ==========================================
# TAMPILAN
# ==========================================

func _set_titles_visible(value: bool) -> void:
	title_1.visible = value
	title_2.visible = value


# ==========================================
# MENU UTAMA
# ==========================================

func _on_play_pressed() -> void:
	print("Play pressed - berpindah ke game...")
	get_tree().change_scene_to_file("res://intro.tscn")


func _on_settings_pressed() -> void:
	vbox_container.visible = false
	_set_titles_visible(false)
	settings_menu.visible = true


func _on_credit_pressed() -> void:
	vbox_container.visible = false
	_set_titles_visible(false)

	credit_panel.visible = true
	is_credits_active = true

	if credits_label and credit_viewport:
		credits_label.position.y = credit_viewport.size.y


func _on_exit_pressed() -> void:
	get_tree().quit()


# ==========================================
# BACK (SETTINGS & CREDITS)
# ==========================================

# Satu fungsi untuk semua tombol Back. Sambungkan semua sinyal pressed() Back ke sini.
func _on_back_pressed() -> void:
	print("Back ditekan")

	# Tutup credits kalau sedang terbuka
	if credit_panel.visible:
		_close_credit()
		return

	# Kalau tidak, tutup settings
	settings_menu.visible = false
	vbox_container.visible = true
	_set_titles_visible(true)


func _close_credit() -> void:
	is_credits_active = false
	credit_panel.visible = false

	vbox_container.visible = true
	_set_titles_visible(true)

	if credits_label:
		credits_label.position.y = initial_label_y


# ==========================================
# SETTINGS
# ==========================================

func _on_sensitivity_changed(value: float) -> void:
	mouse_sensitivity = value
