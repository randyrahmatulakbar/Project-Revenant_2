extends Node3D
# Ruang parkour "poros runtuh" (menggantikan R2 di intro).
# - checkpoint otomatis (CP0..CPn), jatuh ke dasar poros = balik ke checkpoint terakhir + luka kecil
# - petunjuk kecil di bawah layar (node Hints, metadata 'hint'), muncul saat masuk zona
# - Finish = pintu lift di ujung; sinyal `course_finished` dikirim sekali

signal course_finished

@export var fall_damage := 15.0
@export var respawn_flash := 0.35

var _spot_idx := -1
var _spot := Vector3.ZERO
var _done := false
var _flash: ColorRect
var _hint: Label
var _hint_src: Node
var _hint_tw: Tween


func _ready() -> void:
	var cps := $Checkpoints.get_children()
	for i in cps.size():
		var cp: Area3D = cps[i]
		cp.body_entered.connect(_on_checkpoint.bind(i, cp))
	$Hazard.body_entered.connect(_on_hazard)
	$Finish.body_entered.connect(_on_finish)

	var layer := CanvasLayer.new()
	layer.layer = 90
	_flash = ColorRect.new()
	_flash.color = Color(0.0, 0.0, 0.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_flash)
	_hint = Label.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -92
	_hint.offset_bottom = -64
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(0.86, 0.8, 0.7, 1.0))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("outline_size", 4)
	if ResourceLoader.exists("res://font/Rajdhani-Bold.ttf"):
		_hint.add_theme_font_override("font", load("res://font/Rajdhani-Bold.ttf"))
	_hint.modulate.a = 0.0
	layer.add_child(_hint)
	add_child(layer)

	for h in $Hints.get_children():
		h.body_entered.connect(_on_hint.bind(h))
		h.body_exited.connect(_on_hint_exit.bind(h))


func _is_player(b: Node) -> bool:
	return b is CharacterBody3D and b.has_node("Health")


func _on_checkpoint(body: Node, idx: int, cp: Area3D) -> void:
	if not _is_player(body) or idx <= _spot_idx:
		return
	_spot_idx = idx
	_spot = cp.get_node("Spot").global_position


func _on_hazard(body: Node) -> void:
	if not _is_player(body):
		return
	if _spot_idx < 0:
		_spot = $Checkpoints/CP0/Spot.global_position
	body.set_meta("last_hit_by", "The Fall")
	body.set_meta("last_hit_time", Time.get_ticks_msec() / 1000.0)
	body.global_position = _spot
	body.velocity = Vector3.ZERO
	get_tree().call_group("sfx", "play", "hurt")
	var h = body.get_node("Health")
	if h.has_method("take_damage"):
		h.take_damage(fall_damage)
	_flash.color.a = 0.85
	create_tween().tween_property(_flash, "color:a", 0.0, respawn_flash)


func _on_finish(body: Node) -> void:
	if _done or not _is_player(body):
		return
	_done = true
	var lamp: CSGBox3D = $Exit/StatusLamp
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.3, 1.0, 0.45)
	m.emission_enabled = true
	m.emission = Color(0.3, 1.0, 0.45)
	lamp.material = m
	$Exit/DoorLight.light_color = Color(0.3, 1.0, 0.45)
	get_tree().call_group("sfx", "play", "door")
	course_finished.emit()


func _key(action: String) -> String:
	if not InputMap.has_action(action):
		return action.to_upper()
	for e in InputMap.action_get_events(action):
		var t := e.as_text().replace(" (Physical)", "")
		if t != "":
			return t.to_upper()
	return action.to_upper()


func _on_hint(body: Node, area: Node) -> void:
	if not _is_player(body):
		return
	var txt: String = str(area.get_meta("hint", ""))
	txt = txt.replace("{sprint}", _key("sprint")).replace("{jump}", _key("jump")).replace("{crouch}", _key("crouch"))
	_hint.text = txt
	_hint_src = area
	if _hint_tw:
		_hint_tw.kill()
	_hint_tw = create_tween()
	_hint_tw.tween_property(_hint, "modulate:a", 0.9, 0.5)
	_hint_tw.tween_interval(5.0)
	_hint_tw.tween_property(_hint, "modulate:a", 0.0, 1.2)


func _on_hint_exit(body: Node, area: Node) -> void:
	if not _is_player(body) or _hint_src != area:
		return
	if _hint_tw:
		_hint_tw.kill()
	_hint_tw = create_tween()
	_hint_tw.tween_interval(1.5)
	_hint_tw.tween_property(_hint, "modulate:a", 0.0, 1.0)
