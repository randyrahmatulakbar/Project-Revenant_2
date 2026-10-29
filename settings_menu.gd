class_name SettingsMenu
extends CenterContainer

## Ukuran panel (dalam piksel dasar project). Ubah di Inspector instance untuk menyesuaikan.
@export var panel_size: Vector2 = Vector2(560, 600)
@export var font_size: int = 18
@export var title_size: int = 36
@export var label_width: float = 170.0

signal back_pressed
signal sensitivity_changed(value: float)

const SAVE_PATH := "user://settings.cfg"
const BUSES := ["Music", "SFX"]
const FPS_OPTIONS := [0, 30, 60, 90, 120, 144, 165, 240]        # 0 = tanpa batas

# [nama action di Input Map, label di menu]. Action yang tidak ada di Input Map dilewati.
const KEY_ACTIONS := [
	["foward", "Move Forward"],
	["back", "Move Back"],
	["left", "Move Left"],
	["right", "Move Right"],
	["jump", "Jump"],
	["sprint", "Sprint"],
	["crouch", "Crouch / Slide"],
	["shoot", "Shoot"],
	["reload", "Reload"],
	["parry", "Punch / Parry"],
	["interact", "Interact"],
]

@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var sens_slider: HSlider = %SensSlider
@onready var sens_value: Label = %SensValue
@onready var fov_slider: HSlider = %FovSlider
@onready var fov_value: Label = %FovValue
@onready var bright_slider: HSlider = %BrightSlider
@onready var bright_value: Label = %BrightValue
@onready var fullscreen_check: CheckBox = %FullscreenCheck
@onready var vsync_check: CheckBox = %VsyncCheck
@onready var fps_option: OptionButton = %FpsOption
@onready var sprint_toggle_check: CheckBox = %SprintToggleCheck
@onready var tilt_check: CheckBox = %TiltCheck
@onready var bob_check: CheckBox = %BobCheck
@onready var mute_focus_check: CheckBox = %MuteFocusCheck
@onready var reset_button: Button = %ResetButton
@onready var keybinds_button: Button = %KeybindsButton
@onready var back_button: Button = %BackButton

var _wired := false


func _ready() -> void:
	# Tetap jalan saat game di-pause (dipakai di pause menu)
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Selalu penuhi layar induk supaya panel tepat di tengah
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	ensure_buses()
	_ensure_focus_mute()
	apply_saved_keys()
	_build_fps_options()
	_apply_layout()
	_load_into_ui(_load_config())

	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	sens_slider.value_changed.connect(_on_sens_changed)
	fov_slider.value_changed.connect(_on_fov_changed)
	bright_slider.value_changed.connect(_on_bright_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	vsync_check.toggled.connect(_on_vsync_toggled)
	fps_option.item_selected.connect(_on_fps_selected)
	sprint_toggle_check.toggled.connect(_on_sprint_toggle_toggled)
	tilt_check.toggled.connect(_on_tilt_toggled)
	bob_check.toggled.connect(_on_bob_toggled)
	mute_focus_check.toggled.connect(_on_mute_focus_toggled)
	reset_button.pressed.connect(_on_reset_pressed)
	keybinds_button.pressed.connect(_open_keybinds)
	back_button.pressed.connect(_on_back_pressed)
	_wired = true


func _build_fps_options() -> void:
	fps_option.clear()
	for f in FPS_OPTIONS:
		fps_option.add_item("Unlimited" if f == 0 else "%d FPS" % f)


func _load_into_ui(cfg: ConfigFile) -> void:
	master_slider.value = cfg.get_value("audio", "master", 1.0)
	music_slider.value = cfg.get_value("audio", "music", 1.0)
	sfx_slider.value = cfg.get_value("audio", "sfx", 1.0)
	mute_focus_check.button_pressed = cfg.get_value("audio", "mute_unfocused", false)
	sens_slider.value = cfg.get_value("controls", "sensitivity", 1.0)
	fov_slider.value = cfg.get_value("gameplay", "fov", 75.0)
	sprint_toggle_check.button_pressed = cfg.get_value("controls", "sprint_toggle", false)
	tilt_check.button_pressed = cfg.get_value("gameplay", "camera_tilt", true)
	bob_check.button_pressed = cfg.get_value("gameplay", "head_bob", true)
	fullscreen_check.button_pressed = cfg.get_value("video", "fullscreen", false)
	vsync_check.button_pressed = cfg.get_value("video", "vsync", true)
	bright_slider.value = cfg.get_value("video", "brightness", 1.0)
	var idx := FPS_OPTIONS.find(int(cfg.get_value("video", "max_fps", 0)))
	fps_option.select(maxi(idx, 0))
	_refresh_value_labels()
	Engine.set_meta("mouse_sensitivity", sens_slider.value)
	Engine.set_meta("sprint_toggle", sprint_toggle_check.button_pressed)
	Engine.set_meta("fov", fov_slider.value)
	Engine.set_meta("camera_tilt", tilt_check.button_pressed)
	Engine.set_meta("head_bob", bob_check.button_pressed)
	Engine.set_meta("brightness", bright_slider.value)
	Engine.set_meta("mute_unfocused", mute_focus_check.button_pressed)


func _refresh_value_labels() -> void:
	sens_value.text = "%.2fx" % sens_slider.value
	fov_value.text = "%d°" % int(fov_slider.value)
	bright_value.text = "%d%%" % int(round(bright_slider.value * 100.0))


func _apply_layout() -> void:
	$Panel.custom_minimum_size = panel_size
	$Panel/Margin/VBox/Title.add_theme_font_size_override("font_size", title_size)
	var content := $Panel/Margin/VBox/Scroll/Content
	for section in content.get_children():
		if section is HBoxContainer:                       # judul seksi: "// GAMEPLAY" + garis
			for c in section.get_children():
				if c is Label:
					c.add_theme_font_size_override("font_size", font_size - 3)
		else:
			_style_controls(section)
	for b in [back_button, reset_button]:
		b.add_theme_font_size_override("font_size", font_size + 2)
	_style_checkbox(fullscreen_check)
	_style_checkbox(vsync_check)
	_style_checkbox(sprint_toggle_check)
	_style_checkbox(tilt_check)
	_style_checkbox(bob_check)
	_style_checkbox(mute_focus_check)
	RevUI.style_settings(self)                             # skin gaya terminal Revenant (panel, slider, tombol, judul)


func _style_controls(root: Node) -> void:
	for child in root.get_children():
		if child is Label and root is GridContainer:
			child.custom_minimum_size.x = label_width
		if child is Label or child is CheckBox or child is OptionButton or child is Button:
			child.add_theme_font_size_override("font_size", font_size)
		if child.get_child_count() > 0:
			_style_controls(child)


# ---------- Keybinds (menu terpisah: keybind_menu.gd) ----------

func _open_keybinds() -> void:
	var sc = load("res://keybind_menu.gd")
	if sc == null:
		push_warning("SettingsMenu: res://keybind_menu.gd tidak ada")
		return
	var kb: Control = sc.new()
	kb.back_pressed.connect(_close_keybinds.bind(kb))
	$Panel.visible = false
	add_child(kb)


func _close_keybinds(kb: Control) -> void:
	if is_instance_valid(kb):
		kb.queue_free()
	$Panel.visible = true


# API publik untuk menu keybind
static func get_binding(action: String) -> InputEvent:
	return _binding_of(action)


static func event_text(ev: InputEvent) -> String:
	return _event_text(ev) if ev else "—"


static func same_binding(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return a == null and b == null
	return _same_binding(a, b)


static func clone_binding(ev: InputEvent) -> InputEvent:
	return _clone_binding(ev) if ev else null


## Tombol bawaan project (dari Project Settings, bukan Input Map yang sedang aktif).
static func default_binding(action: String) -> InputEvent:
	var d = ProjectSettings.get_setting("input/" + action, null)
	if d is Dictionary:
		for e in d.get("events", []):
			if e is InputEventKey or e is InputEventMouseButton:
				return _clone_binding(e)
	return null


## Terapkan + simpan semua tombol sekaligus. map: {action: InputEvent atau null}
static func commit_bindings(map: Dictionary) -> void:
	for action in map:
		var ev: InputEvent = map[action]
		_set_binding(action, clone_binding(ev))
		_save("keys", action, _serialize(ev) if ev else {})


static func _binding_of(action: String) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			return e
	return null


static func _event_text(ev: InputEvent) -> String:
	return ev.as_text().replace(" (Physical)", "")


static func _same_binding(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ka: int = a.physical_keycode if a.physical_keycode != 0 else a.keycode
		var kb: int = b.physical_keycode if b.physical_keycode != 0 else b.keycode
		return ka == kb
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index
	return false


static func _clone_binding(ev: InputEvent) -> InputEvent:
	if ev is InputEventKey:
		var k := InputEventKey.new()
		k.physical_keycode = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		return k
	if ev is InputEventMouseButton:
		var m := InputEventMouseButton.new()
		m.button_index = ev.button_index
		return m
	return ev


## Hapus tombol keyboard/mouse lama di action itu (joypad dibiarkan), lalu pasang yang baru (null = kosong).
static func _set_binding(action: String, ev: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			InputMap.action_erase_event(action, e)
	if ev:
		InputMap.action_add_event(action, ev)


static func _serialize(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		return {"t": "k", "c": ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode}
	if ev is InputEventMouseButton:
		return {"t": "m", "b": ev.button_index}
	return {}


static func _deserialize(d: Dictionary) -> InputEvent:
	if d.get("t", "") == "k":
		var k := InputEventKey.new()
		k.physical_keycode = int(d.get("c", 0))
		return k
	if d.get("t", "") == "m":
		var m := InputEventMouseButton.new()
		m.button_index = int(d.get("b", 1))
		return m
	return null


## Terapkan tombol tersimpan ke Input Map.
static func apply_saved_keys() -> void:
	var cfg := _load_config()
	if not cfg.has_section("keys"):
		return
	for action in cfg.get_section_keys("keys"):
		if not InputMap.has_action(action):
			continue
		var d = cfg.get_value("keys", action, {})
		if d is Dictionary:
			_set_binding(action, _deserialize(d))


# ---------- Handler ----------

func _on_master_changed(value: float) -> void:
	_apply_bus("Master", value)
	_save("audio", "master", value)


func _on_music_changed(value: float) -> void:
	_apply_bus("Music", value)
	_save("audio", "music", value)


func _on_sfx_changed(value: float) -> void:
	_apply_bus("SFX", value)
	_save("audio", "sfx", value)


func _on_sens_changed(value: float) -> void:
	Engine.set_meta("mouse_sensitivity", value)     # dibaca player-test.gd, langsung berlaku
	sensitivity_changed.emit(value)
	_save("controls", "sensitivity", value)
	_refresh_value_labels()


func _on_fov_changed(value: float) -> void:
	Engine.set_meta("fov", value)
	_save("gameplay", "fov", value)
	_refresh_value_labels()


func _on_bright_changed(value: float) -> void:
	Engine.set_meta("brightness", value)             # player-test.gd menerapkannya ke WorldEnvironment
	_save("video", "brightness", value)
	_refresh_value_labels()


func _on_fullscreen_toggled(on: bool) -> void:
	_apply_fullscreen(on)
	_save("video", "fullscreen", on)


func _on_vsync_toggled(on: bool) -> void:
	_apply_vsync(on)
	_save("video", "vsync", on)


func _on_fps_selected(idx: int) -> void:
	var f: int = FPS_OPTIONS[idx]
	Engine.max_fps = f
	_save("video", "max_fps", f)


func _on_sprint_toggle_toggled(on: bool) -> void:
	Engine.set_meta("sprint_toggle", on)           # dibaca player-test.gd tiap frame, langsung berlaku
	_save("controls", "sprint_toggle", on)


func _on_tilt_toggled(on: bool) -> void:
	Engine.set_meta("camera_tilt", on)
	_save("gameplay", "camera_tilt", on)


func _on_bob_toggled(on: bool) -> void:
	Engine.set_meta("head_bob", on)
	_save("gameplay", "head_bob", on)


func _on_mute_focus_toggled(on: bool) -> void:
	Engine.set_meta("mute_unfocused", on)
	_save("audio", "mute_unfocused", on)


## Kembalikan SEMUA setting (termasuk tombol) ke bawaan.
func _on_reset_pressed() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	InputMap.load_from_project_settings()           # tombol kembali ke yang diatur di Project Settings
	_load_into_ui(ConfigFile.new())                 # semua kontrol ke default; handler tersambung, jadi langsung diterapkan
	_apply_fullscreen(false)
	_apply_vsync(true)
	Engine.max_fps = 0
	_apply_bus("Master", 1.0)
	_apply_bus("Music", 1.0)
	_apply_bus("SFX", 1.0)


func _on_back_pressed() -> void:
	back_pressed.emit()


# ---------- Checkbox yang selalu kelihatan ----------

func _style_checkbox(cb: CheckBox) -> void:
	var s := font_size + 8
	var off := _box_icon(s, false)
	var on := _box_icon(s, true)
	for n in ["unchecked", "unchecked_disabled", "radio_unchecked", "radio_unchecked_disabled"]:
		cb.add_theme_icon_override(n, off)
	for n in ["checked", "checked_disabled", "radio_checked", "radio_checked_disabled"]:
		cb.add_theme_icon_override(n, on)


func _box_icon(s: int, checked: bool) -> ImageTexture:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var border := Color(0.88, 0.85, 0.77, 1.0)
	var fill := Color("dea68a")
	var bg := Color(0.0, 0.0, 0.0, 0.35)
	var t := maxi(2, s / 10)
	for y in s:
		for x in s:
			var edge := x < t or y < t or x >= s - t or y >= s - t
			if edge:
				img.set_pixel(x, y, fill if checked else border)
			elif checked and x >= t + 3 and y >= t + 3 and x < s - t - 3 and y < s - t - 3:
				img.set_pixel(x, y, fill)
			else:
				img.set_pixel(x, y, bg)
	return ImageTexture.create_from_image(img)


# ---------- Helper statis (bisa dipanggil dari mana saja) ----------

static func _load_config() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH) # kalau file belum ada, nilai default dipakai
	return cfg


static func _save(section: String, key: String, value: Variant) -> void:
	var cfg := _load_config()
	cfg.set_value(section, key, value)
	cfg.save(SAVE_PATH)


## Membuat bus Music dan SFX kalau belum ada (cadangan kalau belum dibuat di tab Audio).
static func ensure_buses() -> void:
	for bus_name in BUSES:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


static func _apply_bus(bus_name: String, value: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus == -1:
		return
	AudioServer.set_bus_mute(bus, value <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(value, 0.001)))


static func _apply_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	)


static func _apply_vsync(on: bool) -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED
	)


## Panggil sekali saat game start (mis. di _ready main menu) agar setting tersimpan langsung dipakai.
static func apply_saved() -> void:
	ensure_buses()
	var cfg := _load_config()
	_apply_bus("Master", cfg.get_value("audio", "master", 1.0))
	_apply_bus("Music", cfg.get_value("audio", "music", 1.0))
	_apply_bus("SFX", cfg.get_value("audio", "sfx", 1.0))
	_apply_fullscreen(cfg.get_value("video", "fullscreen", false))
	_apply_vsync(cfg.get_value("video", "vsync", true))
	Engine.max_fps = int(cfg.get_value("video", "max_fps", 0))
	Engine.set_meta("sprint_toggle", cfg.get_value("controls", "sprint_toggle", false))
	Engine.set_meta("mouse_sensitivity", cfg.get_value("controls", "sensitivity", 1.0))
	Engine.set_meta("fov", cfg.get_value("gameplay", "fov", 75.0))
	Engine.set_meta("camera_tilt", cfg.get_value("gameplay", "camera_tilt", true))
	Engine.set_meta("head_bob", cfg.get_value("gameplay", "head_bob", true))
	Engine.set_meta("brightness", cfg.get_value("video", "brightness", 1.0))
	Engine.set_meta("mute_unfocused", cfg.get_value("audio", "mute_unfocused", false))
	apply_saved_keys()
	_ensure_focus_mute()


## true = sprint mode Toggle (tekan sekali nyala, tetap nyala sampai ditekan lagi). false = Hold (tahan tombol).
static func is_sprint_toggle() -> bool:
	if Engine.has_meta("sprint_toggle"):
		return Engine.get_meta("sprint_toggle")
	return _load_config().get_value("controls", "sprint_toggle", false)


## Multiplier sensitivitas (default 1.0). Dipakai di player: look_speed * SettingsMenu.get_sensitivity()
static func get_sensitivity() -> float:
	return _load_config().get_value("controls", "sensitivity", 1.0)


## Pasang satu node kecil di root yang membisukan game saat window kehilangan fokus (kalau opsinya aktif).
static func _ensure_focus_mute() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root.has_node("FocusMute"):
		return
	var n := FocusMute.new()
	n.name = "FocusMute"
	tree.root.add_child.call_deferred(n)


class FocusMute extends Node:
	var _muted := false
	var _prev := false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _notification(what: int) -> void:
		if what == NOTIFICATION_APPLICATION_FOCUS_OUT and bool(Engine.get_meta("mute_unfocused", false)):
			_prev = AudioServer.is_bus_mute(0)
			AudioServer.set_bus_mute(0, true)
			_muted = true
		elif what == NOTIFICATION_APPLICATION_FOCUS_IN and _muted:
			AudioServer.set_bus_mute(0, _prev)
			_muted = false
