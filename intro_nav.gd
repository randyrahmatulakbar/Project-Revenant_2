extends NavigationRegion3D
## Bikin navmesh pas level mulai (runtime), dari semua node yang masuk group "navsource"
## (di intro.tscn: node "map"). Dipakai musuh buat cari jalan di ruangan.

@export var source_group: StringName = &"navsource"
@export var agent_radius: float = 0.6
@export var agent_height: float = 2.0
@export var max_climb: float = 0.5
@export var max_slope: float = 40.0


func _ready() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = source_group
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = agent_radius
	nm.agent_height = agent_height
	nm.agent_max_climb = max_climb
	nm.agent_max_slope = max_slope
	navigation_mesh = nm
	bake_finished.connect(func(): print("Navmesh siap: ", navigation_mesh.get_polygon_count(), " polygon"))
	# tunggu 2 frame biar CSG selesai bikin mesh-nya
	await get_tree().process_frame
	await get_tree().process_frame
	bake_navigation_mesh(true)
