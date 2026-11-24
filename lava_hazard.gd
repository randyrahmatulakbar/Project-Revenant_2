extends Area3D
## Lantai lava: pemain yang jatuh ke sini langsung dipindah ke titik aman (tengah ruangan)
## lalu kena damage. Pasang di Area3D yang menutupi kolam lava (punya CollisionShape3D berbentuk Box).
##
## Deteksi ganda: sinyal body_entered DAN cek posisi pemain di dalam box tiap frame fisika,
## jadi tetap jalan walau collision layer/mask pemain tidak cocok dengan area.

## Titik tujuan (Marker3D) tempat pemain muncul lagi.
@export var respawn_marker: Marker3D
## Damage tiap kali jatuh ke lava.
@export var damage: float = 25.0
## Jeda minimal antar damage (detik) supaya tidak kena dua kali berturut-turut.
@export var cooldown: float = 0.8

var _last_hit := -99.0
var _box: CollisionShape3D


func _ready() -> void:
	collision_mask = 0xFFFFFFFF          # lihat semua layer
	monitoring = true
	body_entered.connect(_on_body_entered)
	for c in get_children():
		if c is CollisionShape3D and c.shape is BoxShape3D:
			_box = c
			break
	if respawn_marker == null:
		# slot Inspector kosong (mis. hilang saat scene disimpan): cari Marker3D bernama "LavaSpawn"
		respawn_marker = get_node_or_null("../LavaSpawn") as Marker3D
		if respawn_marker == null:
			respawn_marker = owner.find_child("LavaSpawn", true, false) as Marker3D if owner else null
		if respawn_marker:
			push_warning("LavaHazard: slot Respawn Marker kosong, otomatis pakai '%s'. Isi slotnya di Inspector biar permanen." % respawn_marker.get_path())
		else:
			push_warning("LavaHazard: Respawn Marker kosong dan node 'LavaSpawn' tidak ketemu, pemain TIDAK akan di-teleport")
	print("LavaHazard siap: %s | marker=%s | box=%s" % [get_path(), respawn_marker, _box != null])
	if _box == null:
		push_warning("LavaHazard: butuh anak CollisionShape3D dengan BoxShape3D")


func _physics_process(_delta: float) -> void:
	if _box == null:
		return
	var p := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if p == null:
		return
	var local := _box.to_local(p.global_position + Vector3.UP * 0.2)
	var h: Vector3 = (_box.shape as BoxShape3D).size * 0.5
	if absf(local.x) <= h.x and absf(local.y) <= h.y and absf(local.z) <= h.z:
		_trigger(p)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body is CharacterBody3D:
		_trigger(body as CharacterBody3D)


func _trigger(player: CharacterBody3D) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_hit < cooldown:
		return
	_last_hit = now
	print("LavaHazard: pemain jatuh ke lava -> teleport + damage ", damage)
	_burn.call_deferred(player)


func _burn(player: CharacterBody3D) -> void:
	if respawn_marker == null:
		return
	player.velocity = Vector3.ZERO
	player.global_position = respawn_marker.global_position
	player.set_meta("last_hit_by", "LAVA")                      # dibaca layar mati
	player.set_meta("last_hit_time", Time.get_ticks_msec())
	_hurt(player)


func _hurt(player: CharacterBody3D) -> void:
	var targets: Array = [player.get_node_or_null("Health"), player]
	for t in targets:
		if t == null:
			continue
		for m in ["take_damage", "damage", "hurt", "apply_damage"]:
			if t.has_method(m):
				t.call(m, damage)
				return
	push_warning("LavaHazard: tidak ada fungsi damage di node Health / player (cek nama fungsinya)")
