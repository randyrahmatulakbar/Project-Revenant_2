extends CanvasLayer

@onready var health_bar = $Control/HealthContainer/HealthBar
@onready var ammo_label = $Control/AmmoContainer/AmmoLabel

# Fungsi untuk update darah
func update_health(current_hp: int, max_hp: int):
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.value = current_hp

# Fungsi untuk update peluru
func update_ammo(current_ammo: int, reserve_ammo: int):
	if ammo_label:
		ammo_label.text = str(current_ammo) + " / " + str(reserve_ammo)
