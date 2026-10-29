extends SceneTree

# Refit the forest scene after changing Terrain3D.
# Run from the project directory with:
# godot --headless --path . --script res://Maps/fit_forest_to_terrain.gd

const MAP_PATH := "res://Maps/main_map.tscn"
const FOREST_SCENE_PATH := "res://Maps/forest.scn"
var tree_part_suffix := RegEx.new()

func _initialize() -> void:
	tree_part_suffix.compile("_(branches|foliage)_\\d+$")
	call_deferred("_refit")


func _refit() -> void:
	var map_scene := load(MAP_PATH) as PackedScene
	if map_scene == null:
		push_error("Could not load %s" % MAP_PATH)
		quit(1)
		return

	var map := map_scene.instantiate()
	root.add_child(map)
	# Let Terrain3D finish loading its height data before sampling it.
	for _frame in 8:
		await process_frame

	var terrain := map.get_node_or_null("Terrain3D") as Terrain3D
	var forest := map.get_node_or_null("Node3D") as Node3D
	if terrain == null or terrain.data == null or forest == null:
		push_error("main_map must contain Terrain3D with loaded data and the forest Node3D.")
		quit(1)
		return

	var forest_root := forest.find_child("GLTF_SceneRootNode", true, false)
	if forest_root == null:
		push_error("Could not find GLTF_SceneRootNode inside the forest scene.")
		quit(1)
		return

	var tree_count := _fit_trees(forest_root, terrain)
	var rock_count := 0
	var log_count := 0
	var grass_vertex_count := 0
	for object in forest_root.get_children():
		var object_3d := object as Node3D
		if object_3d == null:
			continue
		var name := str(object_3d.name).to_lower()
		if name.begins_with("rock_"):
			if _fit_rock_half_submerged(object_3d, terrain):
				rock_count += 1
		elif name.begins_with("log_"):
			if _fit_group_to_ground([object_3d], terrain):
				log_count += 1

	grass_vertex_count = _fit_grass_patches(forest_root, terrain)

	# The forest is instanced under main_map. When packing just that instance,
	# some imported GLTF descendants still have an owner outside the forest
	# root and are silently omitted (including entire tree mesh nodes). Re-own
	# every descendant so the saved forest scene remains complete.
	_set_descendant_owners(forest, forest)

	var fitted := PackedScene.new()
	var pack_error := fitted.pack(forest)
	if pack_error != OK:
		push_error("Could not pack the fitted forest scene: %s" % error_string(pack_error))
		quit(1)
		return

	var save_error := ResourceSaver.save(fitted, FOREST_SCENE_PATH)
	if save_error != OK:
		push_error("Could not save the fitted forest scene: %s" % error_string(save_error))
		quit(1)
		return

	print("Forest fitted and saved: trees=", tree_count, " rocks_half_submerged=", rock_count, " logs_grounded=", log_count, " grass_vertices_fitted=", grass_vertex_count)
	quit(0)


func _set_descendant_owners(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_set_descendant_owners(child, scene_root)


func _fit_trees(forest_root: Node, terrain: Terrain3D) -> int:
	var groups: Dictionary = {}
	for object in forest_root.get_children():
		var object_3d := object as Node3D
		if object_3d == null:
			continue
		var object_name := str(object_3d.name)
		var key := ""
		if object_name.begins_with("tree_copy_"):
			# A tree's imported meshes use separate nodes with the same root XZ.
			# Keep those nodes together so branches and foliage move as one tree.
			key = "tree_copy_%d_%d" % [roundi(object_3d.position.x * 1000.0), roundi(object_3d.position.z * 1000.0)]
		else:
			var match := tree_part_suffix.search(object_name)
			if match != null:
				key = tree_part_suffix.sub(object_name, "")
		if key.is_empty():
			continue
		if not groups.has(key):
			groups[key] = []
		groups[key].append(object_3d)

	var count := 0
	for members in groups.values():
		if _fit_group_to_ground(members, terrain):
			count += 1
	return count


func _fit_group_to_ground(objects: Array, terrain: Terrain3D) -> bool:
	# Use the lowest mesh's own footprint for terrain sampling. A whole tree's
	# combined bounds can be very wide, so its center may sample another slope.
	var bounds := _lowest_mesh_bounds(objects)
	if bounds.size == Vector3.ZERO:
		return false
	var sample := bounds.get_center()
	sample.y = bounds.position.y
	var terrain_height: float = terrain.data.get_height(sample)
	if is_nan(terrain_height):
		return false
	var delta_y := terrain_height - bounds.position.y
	for object in objects:
		var object_3d := object as Node3D
		if object_3d != null:
			object_3d.global_position += Vector3(0.0, delta_y, 0.0)
	return true


func _fit_grass_patches(forest_root: Node, terrain: Terrain3D) -> int:
	var vertex_count := 0
	for group_name in ["grass_fine_9", "grass_lush_10"]:
		var group := forest_root.get_node_or_null(group_name)
		if group == null:
			continue
		for mesh_node in group.find_children("", "MeshInstance3D", true, false):
			var mesh_instance := mesh_node as MeshInstance3D
			var source := mesh_instance.mesh as ArrayMesh
			if source == null:
				continue
			var fitted := ArrayMesh.new()
			fitted.blend_shape_mode = source.blend_shape_mode
			for shape_index in source.get_blend_shape_count():
				fitted.add_blend_shape(source.get_blend_shape_name(shape_index))
			var inverse_transform := mesh_instance.global_transform.affine_inverse()
			for surface_index in source.get_surface_count():
				var arrays := source.surface_get_arrays(surface_index)
				var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				for vertex_index in vertices.size():
					var world_vertex := mesh_instance.global_transform * vertices[vertex_index]
					var terrain_height: float = terrain.data.get_height(world_vertex)
					if is_nan(terrain_height):
						continue
					world_vertex.y = terrain_height + 0.02
					vertices[vertex_index] = inverse_transform * world_vertex
					vertex_count += 1
				arrays[Mesh.ARRAY_VERTEX] = vertices
				fitted.add_surface_from_arrays(
					source.surface_get_primitive_type(surface_index),
					arrays,
					source.surface_get_blend_shape_arrays(surface_index),
					{},
					source.surface_get_format(surface_index)
				)
				fitted.surface_set_material(surface_index, source.surface_get_material(surface_index))
			mesh_instance.mesh = fitted
	return vertex_count


func _fit_rock_half_submerged(rock: Node3D, terrain: Terrain3D) -> bool:
	# Use the actual rock surface rather than its AABB midpoint. This makes the
	# terrain cross the mesh itself even when the rock is irregular or the
	# terrain height changes across its footprint.
	var clearances: Array[float] = []
	for mesh_node in rock.find_children("", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var mesh := mesh_instance.mesh
		for surface_index in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface_index)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			for vertex in vertices:
				var world_vertex := mesh_instance.global_transform * vertex
				var terrain_height: float = terrain.data.get_height(world_vertex)
				if not is_nan(terrain_height):
					clearances.append(world_vertex.y - terrain_height)
	if clearances.is_empty():
		return false
	clearances.sort()
	var median_clearance := clearances[clearances.size() / 2]
	rock.global_position += Vector3(0.0, -median_clearance, 0.0)
	return true


func _lowest_mesh_bounds(objects: Array) -> AABB:
	var have_bounds := false
	var lowest_y := INF
	var lowest := AABB()
	for object in objects:
		var object_3d := object as Node3D
		if object_3d == null:
			continue
		for mesh_node in object_3d.find_children("", "MeshInstance3D", true, false):
			var mesh_instance := mesh_node as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			var mesh_bounds: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
			if mesh_bounds.position.y < lowest_y:
				lowest_y = mesh_bounds.position.y
				lowest = mesh_bounds
				have_bounds = true
	return lowest if have_bounds else AABB()

