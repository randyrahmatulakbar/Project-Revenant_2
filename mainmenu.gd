extends Control

# Referensi Node Utama
@onready var vbox_container: VBoxContainer = $VBoxContainer
@onready var settings_menu: Control = $SettingsMenu
@onready var credit_panel: Panel = $CreditPanel

# Judul (disembunyikan saat Settings / Credit terbuka)
@onready var title_1: Control = $Background/Label
@onready var title_2: Control = $Background/Label2

# Credit sekarang ScrollContainer (scroll manual: mouse wheel, scrollbar, atau panah atas/bawah)
@onready var credit_viewport: ScrollContainer = $CreditPanel/CreditViewport

# Kecepatan scroll saat tombol panah / W / S ditahan
@export var key_scroll_speed: float = 500.0

var is_credits_active: bool = false

# Tetap ada supaya script lain yang membaca nilai ini tidak error.
# Nilainya selalu disinkronkan dari SettingsMenu.
static var mouse_sensitivity: float = 1.0


func _ready() -> void:
	SettingsMenu.apply_saved()
	mouse_sensitivity = SettingsMenu.get_sensitivity()

	settings_menu.visible = false
	credit_panel.visible = false

	settings_menu.back_pressed.connect(_on_back_pressed)
	settings_menu.sensitivity_changed.connect(_on_sensitivity_changed)

	credit_viewport.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _process(delta: float) -> void:
	if is_credits_active:
		var axis := Input.get_axis("ui_up", "ui_down")
		if axis != 0.0:
			credit_viewport.scroll_vertical += int(axis * key_scroll_speed * delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if settings_menu.visible:
			_on_back_pressed()
			get_viewport().set_input_as_handled()
		elif is_credits_active:
			_close_credit()
			get_viewport().set_input_as_handled()


# ==========================================
# TAMPILAN
# ==========================================

func _set_titles_visible(value: bool) -> void:
	title_1.visible = value
	title_2.visible = value


# ==========================================
# TOMBOL MENU UTAMA
# ==========================================

func _on_play_pressed() -> void:
	print("Play pressed - berpindah ke game...")
	get_tree().change_scene_to_file("res://main_level.tscn")


func _on_settings_pressed() -> void:
	vbox_container.visible = false
	_set_titles_visible(false)
	settings_menu.visible = true


func _on_credit_pressed() -> void:
	vbox_container.visible = false
	_set_titles_visible(false)
	credit_panel.visible = true
	is_credits_active = true
	credit_viewport.scroll_vertical = 0


func _on_exit_pressed() -> void:
	get_tree().quit()


# ==========================================
# TOMBOL KEMBALI
# ==========================================

func _on_back_pressed() -> void:
	settings_menu.visible = false
	vbox_container.visible = true
	_set_titles_visible(true)


func _on_back_button_pressed() -> void:
	_on_back_pressed()


func _on_back_credit_pressed() -> void:
	_close_credit()


func _on_back_button_credit_pressed() -> void:
	_close_credit()


func _close_credit() -> void:
	is_credits_active = false
	credit_panel.visible = false
	vbox_container.visible = true
	_set_titles_visible(true)


# ==========================================
# SETTINGS (diurus SettingsMenu)
# ==========================================

func _on_sensitivity_changed(value: float) -> void:
	mouse_sensitivity = value
