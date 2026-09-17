extends CanvasLayer

# Sesuaikan path scene main menu kamu di sini jika beda
const MAIN_MENU_SCENE = "res://main menu/mainmenu.tscn"

@onready var resume_button = $PanelControl/ColorRect/MenuContainer/ResumeButton
@onready var settings_button = $PanelControl/ColorRect/MenuContainer/SettingsButton
@onready var main_menu_button = $PanelControl/ColorRect/MenuContainer/MainMenuButton
@onready var exit_button = $PanelControl/ColorRect/MenuContainer/ExitButton

func _ready():
	hide() # Sembunyikan UI saat game mulai
	
	# Sambungkan sinyal tombol otomatis lewat kodingan
	resume_button.pressed.connect(_on_resume_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

func _unhandled_input(event):
	# "ui_cancel" adalah default mapping untuk tombol ESC di Godot
	if event.is_action_pressed("ui_cancel"):
		toggle_pause()

# Sesuaikan path node Crosshair kamu di scene gameplay
@onready var crosshair = $"../HUD/Crosshair" # contoh path

func toggle_pause():
	var is_paused = !get_tree().paused
	get_tree().paused = is_paused
	visible = is_paused
	
	# Nyari node Label bernama "crosshair" dan nyembunyiin
	var crosshair = get_tree().root.find_child("crosshair", true, false)
	if crosshair:
		crosshair.visible = !is_paused

	if is_paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# --- LOGIKA TOMBOL ---

func _on_resume_pressed():
	toggle_pause()

func _on_settings_pressed():
	get_tree().paused = false # Unpause game dulu
	get_tree().change_scene_to_file("res://main menu/mainmenu.tscn")

func _on_main_menu_pressed():
	get_tree().paused = false # PENTING: Wajib unpause sebelum ganti scene!
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _on_exit_pressed():
	get_tree().quit()
