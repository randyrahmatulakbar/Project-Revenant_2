extends Node
## Spawner musuh bergelombang. Dimulai lewat start() (dipanggil IntroSequence setelah pistol diambil).
## Titik spawn = anak Marker3D dari node "Points".

signal wave_started(index: int, count: int)
signal wave_cleared(index: int)
signal all_cleared

@export var enemy_scenes: Array[PackedScene] = []
## Peluang tiap jenis musuh (urutan sama dengan Enemy Scenes). Kosong = sama rata.
@export var spawn_weights: Array[float] = []
## Jumlah musuh tiap gelombang
@export var waves: Array[int] = [3, 5, 7]

@export_group("Waktu")
@export var first_delay: float = 0.2          # jeda singkat setelah teks hilang (dulu 1.5)
@export var spawn_interval: float = 0.45      # dulu 0.8
@export var wave_delay: float = 2.5           # dulu 4.0
## Tunggu teks (TitleCard) hilang dulu sebelum spawn pertama
@export var wait_for_title: bool = true
@export var title_path: NodePath = ^"../TitleCard"
@export var title_grace: float = 0.8          # kalau teks belum muncul dalam waktu ini, anggap gak ada teks
@export var title_timeout: float = 10.0       # batas tunggu supaya spawn gak macet

@export_group("Batas")
@export var max_alive: int = 6
@export var min_spawn_distance: float = 7.0   # titik spawn lebih dekat dari ini ke player dihindari
@export var loop_forever: bool = false        # true = gelombang terakhir terus bertambah

var _alive := 0
var _running := false
var _wave := 0


func start() -> void:
	if _running:
		return
	_running = true
	_run()


func stop() -> void:
	_running = false


func _run() -> void:
	if enemy_scenes.is_empty():
		push_warning("EnemySpawner: Enemy Scenes masih kosong di Inspector.")
		return
	await _wait_title_gone()
	if not _running:
		return
	await _wait(first_delay)
	while _running:
		var count: int = waves[mini(_wave, waves.size() - 1)]
		if _wave >= waves.size():
			count += (_wave - waves.size() + 1) * 2
		wave_started.emit(_wave + 1, count)
		for i in count:
			while _running and _alive >= max_alive:
				await _wait(0.25)
			if not _running:
				return
			_spawn_one()
			await _wait(spawn_interval)
		while _running and _alive > 0:
			await _wait(0.3)
		if not _running:
			return
		wave_cleared.emit(_wave + 1)
		_wave += 1
		if _wave >= waves.size() and not loop_forever:
			all_cleared.emit()
			_running = false
			return
		await _wait(wave_delay)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


# Tunggu sampai teks di TitleCard gak kelihatan lagi (visible & alpha > 0 pada Label/TextureRect).
func _wait_title_gone() -> void:
	if not wait_for_title:
		return
	var card := get_node_or_null(title_path)
	if card == null:
		return
	var t := 0.0
	while _running and t < title_grace and not _title_showing(card):   # kasih waktu teks muncul
		await _wait(0.05)
		t += 0.05
	t = 0.0
	while _running and t < title_timeout and (get_tree().paused or _title_showing(card)):     # tunggu sampai hilang
		await _wait(0.1)
		t += 0.1


func _title_showing(n: Node, alpha: float = 1.0) -> bool:
	if n is CanvasLayer and not (n as CanvasLayer).visible:
		return false
	if n is CanvasItem:
		var ci := n as CanvasItem
		if not ci.visible:
			return false
		alpha *= ci.modulate.a * ci.self_modulate.a
		if alpha <= 0.05:
			return false
		if n is Label:
			return (n as Label).text.strip_edges() != ""
		if n is RichTextLabel:
			return (n as RichTextLabel).get_parsed_text().strip_edges() != ""
		if n is TextureRect:
			return (n as TextureRect).texture != null
	for c in n.get_children():
		if _title_showing(c, alpha):
			return true
	return false


func _spawn_one() -> void:
	var point := _pick_point()
	if point == null:
		return
	var e := _pick_scene().instantiate()
	# Posisi harus diset SEBELUM add_child: _ready() musuh langsung main suara/debu/flash spawn.
	# Dulu posisi diset sesudahnya, jadi semua efek spawn muncul di titik (0,0,0) dan gak kedengaran.
	var parent := get_parent() as Node3D
	e.position = parent.to_local(point.global_position) if parent else point.global_position
	get_parent().add_child(e)
	_alive += 1
	if e.has_signal("died"):
		e.died.connect(func(_x): _alive -= 1)
	else:
		e.tree_exited.connect(func(): _alive -= 1)


func _pick_point() -> Node3D:
	var holder := get_node_or_null("Points")
	if holder == null:
		return null
	var points: Array = holder.get_children().filter(func(n): return n is Node3D)
	if points.is_empty():
		return null
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return points.pick_random()
	var ok: Array = points.filter(func(p): return p.global_position.distance_to(player.global_position) >= min_spawn_distance)
	if not ok.is_empty():
		return ok.pick_random()
	points.sort_custom(func(a, b): return a.global_position.distance_to(player.global_position) > b.global_position.distance_to(player.global_position))
	return points[0]


func _pick_scene() -> PackedScene:
	var total := 0.0
	for i in enemy_scenes.size():
		total += _weight(i)
	var r := randf() * total
	for i in enemy_scenes.size():
		r -= _weight(i)
		if r <= 0.0:
			return enemy_scenes[i]
	return enemy_scenes.back()


func _weight(i: int) -> float:
	return spawn_weights[i] if i < spawn_weights.size() else 1.0
