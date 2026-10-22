class_name ItemData
extends Resource
## Definisi satu jenis item. Buat file .tres dari resource ini (contoh ada di folder items/).

enum Type { KEY, DOCUMENT, CONSUMABLE, AMMO }

@export var id: StringName = &""            # unik, mis. &"medkit"
@export var display_name: String = ""        # nama yang tampil di UI
@export_multiline var description: String = ""
@export var icon: Texture2D                  # opsional (ikon pixel 16x16)
@export var type: Type = Type.KEY

@export_group("Ukuran di case (gaya RE4)")
@export var grid_w: int = 1                  # lebar dalam kotak
@export var grid_h: int = 1                  # tinggi dalam kotak
@export var allow_rotate: bool = true        # boleh diputar dengan tombol R

@export_group("Stack")
@export var stackable: bool = true
@export var max_stack: int = 3

@export_group("Consumable")
@export var heal_amount: int = 0             # Medkit: 25
@export var armor_amount: int = 0            # Pelat armor: 25

@export_group("Ammo")
@export var ammo_type: StringName = &"pistol"
@export var ammo_min: int = 7                # Kotak peluru: acak 7 sampai 14
@export var ammo_max: int = 14

@export_group("Document / Examine")
@export_multiline var content: String = ""   # isi catatan yang dibaca pemain
