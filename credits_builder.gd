extends VBoxContainer
## Pasang script ini di VBoxContainer yang ada di dalam CreditViewport/MarginContainer.
## Script membangun seluruh credit dari daftar ENTRIES di bawah.
##
## Jenis baris yang tersedia:
##   {"title": "..."}                   -> judul besar di awal
##   {"section": "..."}                 -> header bagian (penanda merah + garis)
##   {"role": "...", "name": "..."}     -> peran di kiri, nama di kanan
##   {"sub": "..."}                     -> sub-judul (mis. "Aset 3D & Lingkungan")
##   {"item": "..."}                    -> baris daftar dengan tanda "-"

# ===== EDIT ISI CREDIT DI SINI =====
const ENTRIES := [
	{"title": "PROJECT REVENANT"},

	{"section": "DIREKSI & DESAIN"},
	{"role": "Game Designer", "name": "Randy Rahmatul Akbar"},

	{"section": "PEMROGRAMAN"},
	{"role": "Gameplay & Systems Programmer", "name": "Randy Rahmatul Akbar"},

	{"section": "LEVEL & LINGKUNGAN"},
	{"role": "Level Designers & Map Artists", "name": "M. Reno Alfian & Laura Aprilianza"},

	{"section": "ARTISTIK, VISUAL & AUDIO"},
	{"role": "UI/UX, 2D Artist & Audio Designer", "name": "Raevan Fadhillah"},

	{"section": "NARRATIVE & STORY"},
	{"role": "Storywriters & Narrative Designers", "name": "Laura Aprilianza & Raevan Fadhillah"},

	{"section": "KONTRIBUSI ASET PIHAK KETIGA"},
	{"sub": "Aset 3D & Lingkungan"},
	{"item": "Kenney.nl (Free 3D Assets & Game Assets)"},
	{"item": "Itch.io Creators (Community Assets)"},
	{"sub": "Audio & Sound Effects"},
	{"item": "YouTube Audio Library"},
	{"item": "Freesound.org & Itch.io Audio Assets"},
	{"item": "UI click sound - Universfield"},
	{"sub": "Font"},
	{"item": "Rajdhani - Indian Type Foundry"},

	{"section": "TERIMA KASIH KHUSUS"},
	{"item": "Guru Pembimbing - Pak Maul & Bu Annisa"},
	{"item": "SMKN 21 Jakarta"},
	{"item": "Komunitas Godot Engine Indonesia"},
]
# ===================================

const COLOR_ROLE := Color("c99a7e")
const COLOR_NAME := Color("eadccf")
const COLOR_TICK := Color("c0392b")
const COLOR_LINE := Color(0.55, 0.42, 0.34, 0.30)

@export var role_width: float = 300.0
@export var role_font_size: int = 15
@export var name_font_size: int = 19
@export var section_font_size: int = 17
@export var title_font_size: int = 28
@export var row_gap: int = 8
@export var section_gap: int = 22
@export var letter_spacing: int = 2


func _ready() -> void:
	_style_header()
	_build()


func _build() -> void:
	# Hapus isi lama (Spacer, CreditText, Spacer2)
	for child in get_children():
		child.queue_free()

	add_theme_constant_override("separation", row_gap)

	var first_section := true
	for entry in ENTRIES:
		if entry.has("title"):
			_add_title(entry["title"])
		elif entry.has("section"):
			if not first_section:
				_add_gap(section_gap)
			first_section = false
			_add_section(entry["section"])
		elif entry.has("role"):
			_add_row(entry["role"], entry.get("name", ""))
		elif entry.has("sub"):
			_add_sub(entry["sub"])
		elif entry.has("item"):
			_add_item(entry["item"])

	# Ruang kosong di akhir supaya teks terakhir keluar penuh dari layar
	_add_gap(60)


# ---------- Pembuat elemen ----------

func _add_gap(height: float) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	add_child(gap)


func _add_title(text: String) -> void:
	var label := _make_label(text.to_upper(), title_font_size, COLOR_NAME)
	add_child(label)
	_apply_spacing(label)
	_add_gap(6)


func _add_section(text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	row.add_child(_make_tick())
	var label := _make_label(text.to_upper(), section_font_size, COLOR_ROLE)
	row.add_child(label)
	_apply_spacing(label)
	_add_line()


func _add_row(role_text: String, name_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)

	var role := _make_label(role_text, role_font_size, COLOR_ROLE)
	role.custom_minimum_size = Vector2(role_width, 0)
	role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	role.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(role)

	var name_label := _make_label(name_text, name_font_size, COLOR_NAME)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name_label)


func _add_sub(text: String) -> void:
	_add_gap(4)
	var label := _make_label(text, name_font_size, COLOR_NAME)
	add_child(label)


func _add_item(text: String) -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	add_child(margin)
	var label := _make_label("-  " + text, role_font_size + 2, COLOR_ROLE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	margin.add_child(label)


func _add_line() -> void:
	var line := ColorRect.new()
	line.color = COLOR_LINE
	line.custom_minimum_size = Vector2(0, 1)
	add_child(line)


# ---------- Helper ----------

func _make_label(text: String, font_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_px)
	label.add_theme_color_override("font_color", color)
	return label


# Penanda merah miring (gaya HUD)
func _make_tick() -> Panel:
	var tick := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_TICK
	sb.skew = Vector2(-0.35, 0)
	tick.add_theme_stylebox_override("panel", sb)
	tick.custom_minimum_size = Vector2(6, 16)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return tick


# Menambah jarak antar huruf (font diambil dari theme). Panggil setelah label masuk tree.
func _apply_spacing(label: Label) -> void:
	var base := label.get_theme_font("font", "Label")
	if base == null:
		return
	var variation := FontVariation.new()
	variation.base_font = base
	variation.spacing_glyph = letter_spacing
	label.add_theme_font_override("font", variation)


# Rapikan judul "CREDITS" (opsional, aman kalau node tidak ketemu)
func _style_header() -> void:
	var title := get_node_or_null("../../../CreditTitle") as Label
	if title == null:
		return
	title.text = "CREDITS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", COLOR_TICK)
