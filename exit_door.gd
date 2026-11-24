extends Node3D
## Pintu keluar room. Terkunci sampai terminal di-hack (HackBody.hacked), lalu pintu naik terbuka.
## Pasang di node "Exit". Anak yang dipakai: Panel1 (pintu), StatusLamp1, DoorLight, HackBody (hack_terminal.gd).
## Semua pencarian node aman: kalau ada yang tidak ketemu, hanya peringatan, tidak crash.

signal opened

@export var panel_path: NodePath = ^"Panel1"
@export var lamp_path: NodePath = ^"StatusLamp1"
@export var light_path: NodePath = ^"DoorLight"
@export var terminal_path: NodePath = ^"HackBody"
@export var open_height := 3.3
@export var open_time := 2.6

const RED := Color(1.0, 0.12, 0.08)
const GREEN := Color(0.2, 1.0, 0.35)

var is_open := false
var _panel: Node3D
var _lamp: CSGShape3D
var _lamp_mat: StandardMaterial3D
var _light: Light3D
var _pulse: Tween


func _ready() -> void:
	_panel = get_node_or_null(panel_path) as Node3D
	_lamp = get_node_or_null(lamp_path) as CSGShape3D
	_light = get_node_or_null(light_path) as Light3D
	if _panel == null:
		push_warning("ExitDoor: Panel '%s' tidak ketemu" % panel_path)
	if _lamp:
		_lamp_mat = StandardMaterial3D.new()          # material sendiri, tidak mengubah yang dipakai node lain
		_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_lamp.set("material", _lamp_mat)
	_set_lamp(RED, 1.0)
	_pulse = create_tween().set_loops()
	_pulse.tween_method(_pulse_step, 0.0, 1.0, 0.6)
	_pulse.tween_method(_pulse_step, 1.0, 0.0, 0.6)

	var t := get_node_or_null(terminal_path)
	if t and t.has_signal("hacked"):
		t.connect("hacked", open)
	else:
		push_warning("ExitDoor: terminal '%s' tidak ketemu / tidak punya sinyal 'hacked', pintu tidak akan terbuka" % terminal_path)


func open() -> void:
	if is_open:
		return
	is_open = true
	if _pulse:
		_pulse.kill()
	_set_lamp(GREEN, 1.0)
	if _panel:
		var tw := create_tween()
		tw.tween_property(_panel, "global_position:y", _panel.global_position.y + open_height, open_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	opened.emit()


func _pulse_step(k: float) -> void:
	_set_lamp(RED, lerpf(0.35, 1.0, k))


func _set_lamp(c: Color, energy: float) -> void:
	if _lamp_mat:
		_lamp_mat.albedo_color = Color(c.r * energy, c.g * energy, c.b * energy)
	if _light:
		_light.light_color = c
