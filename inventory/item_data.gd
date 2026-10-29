class_name ItemData
extends Resource
## Definisi satu jenis item. Buat file .tres dari resource ini (contoh ada di folder items/).

enum Type { KEY, DOCUMENT, CONSUMABLE, AMMO, EQUIPMENT, WEAPON }   # EQUIPMENT dan WEAPON ditambah di belakang supaya .tres lama tidak berubah

@export var id: StringName = &""            # unik, mis. &"medkit"
@export var display_name: String = ""        # nama yang tampil di UI
@export_multiline var description: String = ""
@export var icon: Texture2D                  # opsional (ikon pixel 16x16)
@export var type: Type = Type.KEY

@export_group("Ukuran di case (gaya RE4)")
@export var grid_w: int = 1                  # lebar dalam kotak
@export var grid_h: int = 1                  # tinggi dalam kotak
@export var allow_rotate: bool = true        # boleh diputar dengan tombol R
@export var shape: Array[Vector2i] = []     # bentuk khusus (L, T, dll) = daftar kotak (x, y). Kosong = persegi panjang grid_w x grid_h.
                                             # Untuk bentuk khusus, grid_w / grid_h isi dengan ukuran kotak pembatasnya.

@export_group("Stack")
@export var stackable: bool = true
@export var max_stack: int = 3

@export_group("Consumable")
@export var heal_amount: int = 0             # Medkit: 25
@export var armor_amount: int = 0            # Pelat armor: 25

@export_group("Ammo")
@export var ammo_type: StringName = &"pistol"
@export var mag_rounds: int = 6               # isi 1 magazine (item peluru = 1 magazine, memakai kotak di case, tidak bisa ditumpuk)
@export var ammo_min: int = 7                # (tidak dipakai lagi sejak peluru jadi magazine)
@export var ammo_max: int = 14

@export_group("Document / Examine")
@export_multiline var content: String = ""   # isi catatan yang dibaca pemain
