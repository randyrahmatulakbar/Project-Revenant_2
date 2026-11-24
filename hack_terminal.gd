extends StaticBody3D
## Terminal yang harus di-hack: tekan interact lalu TAHAN sampai bar penuh.
## Dilepas atau menjauh = progres turun lagi. Selesai -> sinyal `hacked` (dipakai exit_door.gd).
##
## Pasang pada StaticBody3D yang punya CollisionShape3D (sedikit lebih besar dari model terminal).
## Belum diuji di Godot.

signal hacked
signal progress_changed(value: float)

const PICK_LAYER: int = 1 << 19                 # sama seperti chest.gd, supaya raycast interact pemain kena

@export var interact_text := "HACK"
@export var hack_time := 4.0                    # detik menahan tombol sampai selesai
@export var decay_speed := 1.5                  # progres turun segini kali lebih cepat saat dilepas
@export var max_distance := 4.5                 # lebih jauh dari ini = hack terputus
@export var action := "interact"
@export var label_offset := Vector3(-0.5, 0.95, 0.0)   # posisi tulisan dari titik node ini
@export var color_locked := Color(1.0, 0.18, 0.1)
@export var color_hacking := Color(1.0, 0.75, 0.15)
@export var color_ok := Color(0.25, 1.0, 0.4)

var progress := 0.0
var is_hacked := false
var _hacking := false
var _player: Node3D
var _label: Label3D


func _ready() -> void:
	collision_layer = PICK_LAYER
	collision_mask = 0
	_label = Label3D.new()
	_label.name = "HackLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.shaded = false
	_label.double_sided = true
	_label.pixel_size = 0.004
	_label.font_size = 44
	_label.outline_size = 10
	_label.outline_modulate = Color(0, 0, 0, 0.9)
	_label.position = label_offset
	add_child(_label)
	_update_label()


func interact() -> void:
	if is_hacked:
		return
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_hacking = true


func _process(delta: float) -> void:
	if is_hacked:
		return
	var holding := _hacking and Input.is_action_pressed(action) \
		and _player != null and _player.global_position.distance_to(global_position) <= max_distance
	var before := progress
	if holding:
		progress = minf(1.0, progress + delta / maxf(hack_time, 0.1))
	else:
		_hacking = false
		if progress > 0.0:
			progress = maxf(0.0, progress - delta / maxf(hack_time, 0.1) * decay_speed)
	if progress != before:
		progress_changed.emit(progress)
		_update_label()
	if progress >= 1.0:
		_finish()


func _finish() -> void:
	is_hacked = true
	_hacking = false
	collision_layer = 0                      # tidak bisa di-interact lagi, prompt hilang
	_update_label()
	hacked.emit()


func _update_label() -> void:
	if _label == null:
		return
	if is_hacked:
		_label.text = "ACCESS GRANTED"
		_label.modulate = color_ok
	elif progress > 0.0:
		var n := int(round(progress * 10.0))
		_label.text = "HACKING\n[%s%s] %d%%" % ["#".repeat(n), "-".repeat(10 - n), int(progress * 100.0)]
		_label.modulate = color_hacking
	else:
		_label.text = "[ LOCKED ]"
		_label.modulate = color_locked
