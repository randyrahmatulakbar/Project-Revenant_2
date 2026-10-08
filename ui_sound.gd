extends Node
## Autoload: bunyi klik otomatis untuk SEMUA tombol (Button, CheckBox, dll) di seluruh game.

const CLICK_SOUND: AudioStream = preload("res://sound/click.mp3")

@export var volume_db: float = -4.0

var _player: AudioStreamPlayer


func _ready() -> void:
	# Tetap bunyi saat game di-pause (pause menu)
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Pastikan bus SFX ada sebelum dipakai
	SettingsMenu.ensure_buses()

	_player = AudioStreamPlayer.new()
	_player.stream = CLICK_SOUND
	_player.volume_db = volume_db
	_player.bus = "SFX"
	add_child(_player)

	# Hubungkan semua tombol yang muncul, sekarang maupun nanti
	get_tree().node_added.connect(_on_node_added)
	_hook_existing(get_tree().root)


func _hook_existing(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_hook_existing(child)


func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.pressed.is_connected(_play_click):
		node.pressed.connect(_play_click)


func _play_click() -> void:
	_player.play()
