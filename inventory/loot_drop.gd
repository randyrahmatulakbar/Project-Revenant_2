extends Node3D
## Tumpukan loot di lantai (dibuat LootManager). items = [{"item": ItemData, "amount": int}, ...]

const Catalog = preload("item_catalog.gd")

var items: Array = []
var lifetime := 0.0            # 0 = tidak pernah hilang
var _t := 0.0
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _light: OmniLight3D
var _base_y := 0.0


func _ready() -> void:
	add_to_group("loot_drop")
	var col := _pile_color()
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.2, 0.3)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = col.darkened(0.55)
	_mat.emission_enabled = true
	_mat.emission = col
	_mat.emission_energy_multiplier = 1.4
	bm.material = _mat
	_mesh.mesh = bm
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_light = OmniLight3D.new()
	_light.light_color = col
	_light.light_energy = 0.9
	_light.omni_range = 2.6
	_light.shadow_enabled = false
	add_child(_light)
	_base_y = _mesh.position.y
	scale = Vector3.ONE * 0.1
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _pile_color() -> Color:
	var best := Color(0.9, 0.85, 0.8)
	for it in items:
		var item: ItemData = it.item
		if item.type == ItemData.Type.EQUIPMENT or item.type == ItemData.Type.WEAPON:
			return Catalog.color_of(item)              # ada artefak / senjata -> paling menonjol
		best = Catalog.color_of(item)
	return best


func _process(delta: float) -> void:
	_t += delta
	if _mesh:
		_mesh.position.y = _base_y + 0.08 * sin(_t * 2.4)
		_mesh.rotation.y += delta * 1.1
	if lifetime > 0.0:
		var left := lifetime - _t
		if left < 6.0 and _mat:
			_mat.emission_energy_multiplier = 0.6 + 0.8 * absf(sin(_t * 9.0))       # berkedip sebelum hilang
		if left <= 0.0:
			queue_free()


## Gabungkan loot baru ke tumpukan ini (item yang sama dijumlah). Dipakai saat dua drop berdekatan.
func add_items(extra: Array) -> void:
	for e in extra:
		var found := false
		if e.has("rounds"):                            # magazine dengan isi sendiri tidak digabung
			items.append(e)
			continue
		for it in items:
			if it.item.id == e.item.id and not it.has("rounds"):
				it.amount = int(it.amount) + int(e.amount)
				found = true
				break
		if not found:
			items.append({"item": e.item, "amount": int(e.amount)})
	_t = 0.0
	var col := _pile_color()
	if _mat:
		_mat.albedo_color = col.darkened(0.55)
		_mat.emission = col
	if _light:
		_light.light_color = col
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 1.25, 0.1)
	tw.tween_property(self, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func has_unique(id: StringName) -> bool:
	for it in items:
		if it.item.id == id:
			return true
	return false
