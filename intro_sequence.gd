extends Node
## Mengatur urutan: tangan kosong -> ambil pistol -> ruangan terang
## -> HUD senjata masuk dengan animasi -> musuh spawn.

@export var pickup: Node3D
@export var fist_hud: CanvasLayer
@export var room_lights: Node3D
@export var spawner: Node
@export var light_energy: float = 3.0

var player: Node
var hud: Node
var _flash: ColorRect


func _ready() -> void:
	pickup = pickup if pickup else get_node_or_null("../PistolPickup")
	fist_hud = fist_hud if fist_hud else get_node_or_null("../HUDIntro")
	room_lights = room_lights if room_lights else get_node_or_null("../RoomLights")
	spawner = spawner if spawner else get_node_or_null("../EnemySpawner")

	player = get_tree().get_first_node_in_group("player")
	hud = get_tree().get_first_node_in_group("hud")

	# awal: HUD tempur mati, HUD tangan nyala, belum boleh nembak
	if hud and hud.has_method("enter_intro_mode"):
		hud.enter_intro_mode(fist_hud)
	if room_lights:
		for l in room_lights.get_children():
			if l is Light3D:
				l.light_energy = 0.0

	_make_flash()
	if pickup:
		pickup.picked_up.connect(_on_picked_up)


func _on_picked_up() -> void:
	_do_flash()
	_lights_on()

	await get_tree().create_timer(0.35).timeout
	if hud and hud.has_method("play_enter_animation"):
		await hud.play_enter_animation()

	if spawner and spawner.has_method("start"):
		spawner.start()


# ruangan nyala satu-satu, kedip-kedip kayak lampu neon
func _lights_on() -> void:
	if room_lights == null:
		return
	var i := 0
	for l in room_lights.get_children():
		if l is Light3D:
			var tw := create_tween()
			tw.tween_interval(i * 0.14)
			tw.tween_property(l, "light_energy", light_energy * 1.6, 0.05)
			tw.tween_property(l, "light_energy", light_energy * 0.2, 0.06)
			tw.tween_property(l, "light_energy", light_energy * 1.3, 0.05)
			tw.tween_property(l, "light_energy", light_energy * 0.4, 0.08)
			tw.tween_property(l, "light_energy", light_energy, 0.35)
			i += 1


func _make_flash() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_flash = ColorRect.new()
	_flash.color = Color(1.0, 0.92, 0.8)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	layer.add_child(_flash)


func _do_flash() -> void:
	var tw := create_tween()
	tw.tween_property(_flash, "modulate:a", 0.85, 0.05)
	tw.tween_property(_flash, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_OUT)
