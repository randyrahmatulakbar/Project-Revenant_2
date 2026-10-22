class_name Pickup
extends StaticBody3D

signal picked_up

@export var item: ItemData
@export_range(1, 999, 1) var amount: int = 1
@export var verb: String = "AMBIL"
@export var interact_text: String = ""

const PICK_LAYER: int = 1 << 19 # Layer 20

func _ready() -> void:
	collision_layer = PICK_LAYER
	collision_mask = 0

	if interact_text.is_empty() and item != null:
		interact_text = "%s %s" % [
			verb,
			item.display_name.to_upper()
		]

	if item == null:
		push_warning("Pickup belum diberi ItemData: " + str(get_path()))


func interact() -> void:
	if item == null:
		push_warning("Loot tidak bisa diambil: ItemData belum diatur.")
		return

	if amount <= 0:
		push_warning("Jumlah loot harus lebih dari 0.")
		return

	if Inventory.add_item(item, amount):
		picked_up.emit()
		queue_free()
