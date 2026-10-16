extends Node

enum spawnerType {
	TarotCardSpawner,
	BodyPartSpawner
}

@export var object_scene: PackedScene
@export var object_scenes: Array[PackedScene] = []
@export var spawn_points: Array[Marker3D]
@export var objects_to_spawn = 1
@export var object_spawner_type: spawnerType
@export var super_tarot_scene: PackedScene

var spawned_objects: Array[Node] = []


func spawn_objects(peer_id: int = -1) -> void:
	clear_objects()

	if object_spawner_type == spawnerType.BodyPartSpawner:
		var n := 0
		for pid in GameManager.players.keys():
			for t in 4:
				_spawn_object(
					spawn_points[n % spawn_points.size()],
					pid,
					t
				)
				n += 1
		return

	var available_scenes: Array[PackedScene] = object_scenes.duplicate()
	available_scenes.shuffle()

	for i in range(spawn_points.size()):
		var scene_to_spawn: PackedScene = object_scene

		if i < available_scenes.size():
			scene_to_spawn = available_scenes[i]

		_spawn_object(spawn_points[i], -1, -1, scene_to_spawn)


func spawn_super_tarot() -> void:
	if not multiplayer.is_server():
		return

	if super_tarot_scene == null:
		push_warning("SpawnManager: Super Tarot scene is not assigned")
		return

	if spawn_points.is_empty():
		push_warning("SpawnManager: No Tarot spawn points available")
		return

	var random_spawn_point: Marker3D = spawn_points.pick_random()

	_spawn_object(
		random_spawn_point,
		-1,
		-1,
		super_tarot_scene
	)


func _spawn_object(
	spawn_point: Marker3D,
	owner_id: int = -1,
	part_type: int = -1,
	scene_to_spawn: PackedScene = null
) -> void:
	if spawn_point == null:
		return

	if scene_to_spawn == null:
		scene_to_spawn = object_scene

	if scene_to_spawn == null:
		return

	print("Spawn_Point: ", spawn_point.global_position)

	var object := scene_to_spawn.instantiate()
	object.name = "Object_" + str(spawned_objects.size())

	if owner_id >= 0:
		object.owner_id = owner_id
		object.part_type = part_type

		var c: int = GameManager.players[owner_id]["color"]
		object.part_color = GameManager.PLAYER_COLOR_VALUES[c]

	var world_node: Node = null

	if has_node("/root/GameMode/SubViewportContainer/SubViewport/WorldObjects"):
		world_node = get_node(
			"/root/GameMode/SubViewportContainer/SubViewport/WorldObjects"
		)
	elif get_tree() and get_tree().current_scene:
		world_node = get_tree().current_scene.find_child(
			"WorldObjects", true, false
		)

	if world_node == null:
		world_node = get_parent()

	world_node.add_child(object, true)
	object.global_position = spawn_point.global_position
	spawned_objects.append(object)


func clear_objects() -> void:
	for object in spawned_objects:
		if is_instance_valid(object):
			object.queue_free()

	spawned_objects.clear()


func _ready() -> void:
	if object_spawner_type == spawnerType.TarotCardSpawner:
		GameManager.tarot_card_spawner = self

	if object_spawner_type == spawnerType.BodyPartSpawner:
		GameManager.body_part_spawner = self

	if multiplayer.is_server():
		# Whenever a client connects, call spawn_objects.
		multiplayer.peer_connected.connect(spawn_objects)


func _process(delta: float) -> void:
	pass
