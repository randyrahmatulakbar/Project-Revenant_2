extends CanvasLayer
## Teks credit intro: muncul LANGSUNG (tanpa adnimasi) saat player masuk trigger.
## Taruh Marker3D bernama teks1, teks2, ... di belokan. Isi Lines sesuai urutan marker.

@export var font: Font
@export var font_size := 32
@export var vertical_pos := 0.5          # 0.5 = tengah layar
@export var hold_time := 3.0             # lama teks tampil (detik), 0 = tetap sampai teks berikutnya
@export var trigger_size := Vector3(3, 3, 3)
@export var normal_color := Color("f2eadf")
@export var accent_color := Color("ffa51f")
@export var lines: PackedStringArray = PackedStringArray([
	"[accent]KELOMPOK 2[/accent] PRESENTS",
	"A [accent]GAME[/accent] BY [accent]----[/accent]",
])

var _label: RichTextLabel
var _showing := false
var _hide_tween: Tween


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS   # supaya bisa disembunyiin saat pause
	_build_label()
	for i in lines.size():
		var marker := get_parent().find_child("teks%d" % (i + 1), true, false) as Node3D
		if marker == null:
			push_warning("Credits: marker 'teks%d' tidak ketemu" % (i + 1))
			continue
		_make_trigger(marker, i)


func _process(_delta: float) -> void:
	_label.visible = _showing and not get_tree().paused


func _build_label() -> void:
	var f: Font = font if font else ThemeDB.fallback_font
	var h := f.get_height(font_size)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.scroll_active = false
	_label.clip_contents = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.anchor_top = vertical_pos
	_label.anchor_bottom = vertical_pos
	_label.offset_left = 0.0
	_label.offset_right = 0.0
	_label.offset_top = -h * 0.5          # tinggi kotak = tinggi 1 baris, jadi pas di tengah
	_label.offset_bottom = h * 0.5
	_label.add_theme_font_size_override("normal_font_size", font_size)
	_label.add_theme_color_override("default_color", normal_color)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	if font:
		_label.add_theme_font_override("normal_font", font)
	_label.visible = false
	add_child(_label)


func _make_trigger(marker: Node3D, index: int) -> void:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 0xFFFFFFFF
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = trigger_size
	shape.shape = box
	area.add_child(shape)
	marker.add_child(area)
	area.body_entered.connect(func(body: Node3D):
		if body.is_in_group("player"):
			area.set_deferred("monitoring", false)    # sekali saja
			_show_line(lines[index])
	)


func _show_line(raw: String) -> void:
	var tag := "[color=#%s]" % accent_color.to_html(false)
	var text := raw.replace("[accent]", tag).replace("[/accent]", "[/color]")
	_label.text = "[center]" + text + "[/center]"
	_showing = true
	if _hide_tween:
		_hide_tween.kill()
	if hold_time > 0.0:
		_hide_tween = create_tween()
		_hide_tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)   # hitungan berhenti saat pause
		_hide_tween.tween_interval(hold_time)
		_hide_tween.tween_callback(func(): _showing = false)
