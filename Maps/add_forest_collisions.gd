extends SceneTree

## Generates collision for rocks, fallen sticks/logs, and tree trunks in
## forest.scn. Trunk capsules are positioned and sized from the bark mesh's
## actual base vertices. Foliage, grass, and bushes are always excluded.
## Run from the project folder with:
## godot --headless --path . --script res://Maps/add_forest_collisions.gd

const FOREST_PATH := "res://Maps/forest.scn"
const GENERATED_PREFIX := "ForestCollisionGenerated_"
const MIN_TREE_COLLIDER_HEIGHT := 3.0
func _initialize() -> void:
	call_deferred("_bake")


func _bake() -> void:
	var packed := load(FOREST_PATH) as PackedScene
	if packed == null:
		push_error("Could not load %s" % FOREST_PATH)
		quit(1)
		return

	var forest := packed.instantiate()
	root.add_child(forest)
	await process_frame

	var asset_root := forest.find_child("GLTF_SceneRootNode", true, false)
	if asset_root == null:
		push_error("Could not find GLTF_SceneRootNode in %s" % FOREST_PATH)
		quit(1)
		return

	var removed_foliage := _remove_foliage_collisions(asset_root)
	var generated := 0
	var skipped := 0
	for asset in asset_root.get_children():
		if not asset is Node3D:
			continue
		var asset_name := str(asset.name).to_lower()
		# Also clean output from older runs on source meshes that are no longer
		# collision targets.
		_remove_generated_colliders(asset)
		if _is_excluded(asset_name):
			skipped += 1
			continue

		var category := _category(asset_name)
		if category.is_empty():
			continue

		var meshes := _collect_meshes(asset)
		if meshes.is_empty():
			continue

		if category == "tree":
			# tree_copy groups rely on a paired foliage instance to distinguish
			# intact placements; named *_branches_* groups are explicit tree trunks
			# and should still get a collider if their foliage node is absent.
			if asset_name.begins_with("tree_copy_") and not _has_foliage_counterpart(asset, asset_root):
				continue
			for mesh_instance in meshes:
				if _is_bark_mesh(mesh_instance) and mesh_instance.mesh.get_aabb().size.y >= MIN_TREE_COLLIDER_HEIGHT and _add_trunk_collider(mesh_instance):
					generated += 1
		else:
			for mesh_instance in meshes:
				if _add_convex_collider(mesh_instance, category):
					generated += 1

	var baked := PackedScene.new()
	var pack_error := baked.pack(forest)
	if pack_error != OK:
		push_error("Could not pack forest scene: %s" % error_string(pack_error))
		quit(1)
		return
	var save_error := ResourceSaver.save(baked, FOREST_PATH)
	if save_error != OK:
		push_error("Could not save forest scene: %s" % error_string(save_error))
		quit(1)
		return

	print("Forest collisions saved: %d colliders; removed %d old foliage collider(s); skipped %d foliage/grass/bush group(s)." % [generated, removed_foliage, skipped])
	quit(0)


func _is_excluded(name: String) -> bool:
	for word in ["foliage", "leaf", "leaves", "grass", "bush", "shrub"]:
		if name.contains(word):
			return true
	return false


func _category(name: String) -> String:
	if name.begins_with("rock_"):
		return "rock"
	if name.begins_with("log_") or name.begins_with("stick_"):
		return "log"
	# Imported center-forest trees use paired *_branches_* and *_foliage_*
	# groups instead of the tree_copy_* naming used by the outer forest.
	if name.begins_with("tree_copy_") or name.contains("_branches_"):
		return "tree"
	return ""


func _collect_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		for child in current.get_children():
			if child is MeshInstance3D and child.mesh != null:
				found.append(child as MeshInstance3D)
			stack.append(child)
	return found


func _is_bark_mesh(mesh_instance: MeshInstance3D) -> bool:
	var identifying_text := str(mesh_instance.name).to_lower()
	var parent := mesh_instance.get_parent()
	while parent != null and parent != mesh_instance.owner:
		identifying_text += " " + str(parent.name).to_lower()
		parent = parent.get_parent()
	var mesh := mesh_instance.mesh
	for surface_index in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface_index)
		if material != null:
			identifying_text += " " + material.resource_name.to_lower()
	if _is_excluded(identifying_text):
		return false
	return identifying_text.contains("bark") or identifying_text.contains("branch") or identifying_text.contains("trunk") or identifying_text.contains("wood")


func _has_foliage_counterpart(tree_asset: Node3D, asset_root: Node) -> bool:
	var tree_name := str(tree_asset.name).to_lower()
	var match_prefix := ""
	if tree_name.contains("_branches_"):
		match_prefix = tree_name.split("_branches_")[0] + "_foliage_"
	for candidate in asset_root.get_children():
		if not candidate is Node3D:
			continue
		if not match_prefix.is_empty():
			if str(candidate.name).to_lower().begins_with(match_prefix) and _contains_foliage_mesh(candidate):
				return true
		elif tree_name.begins_with("tree_copy_") and str(candidate.name).to_lower().begins_with("tree_copy_"):
			if tree_asset.global_position.distance_to((candidate as Node3D).global_position) <= 0.05 and _contains_foliage_mesh(candidate):
				return true
	return false


func _contains_foliage_mesh(node: Node) -> bool:
	for mesh_instance in _collect_meshes(node):
		var mesh := mesh_instance.mesh
		for surface_index in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface_index)
			if material == null:
				continue
			var material_name := material.resource_name.to_lower()
			if material_name.contains("leaf") or material_name.contains("foliage"):
				return true
	return false


func _add_trunk_collider(mesh_instance: MeshInstance3D) -> bool:
	var bounds := mesh_instance.mesh.get_aabb()
	if bounds.size.y <= 0.1:
		return false
	var base_vertices: Array[Vector2] = []
	for surface_index in mesh_instance.mesh.get_surface_count():
		var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for vertex in vertices:
			if vertex.y <= bounds.position.y + bounds.size.y * 0.12:
				base_vertices.append(Vector2(vertex.x, vertex.z))
	var stem_center: Vector2
	var stem_radius: float
	if base_vertices.is_empty():
		# A few imported center trees have no vertices near the mesh's lowest
		# 12%, so fall back to the mesh bounds instead of omitting the trunk.
		stem_center = Vector2(bounds.position.x + bounds.size.x * 0.5, bounds.position.z + bounds.size.z * 0.5)
		stem_radius = clampf(minf(bounds.size.x, bounds.size.z) * 0.25, 0.12, 0.4)
	else:
		base_vertices.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var center_x := base_vertices[base_vertices.size() / 2].x
		base_vertices.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
		var center_z := base_vertices[base_vertices.size() / 2].y
		stem_center = Vector2(center_x, center_z)
		var radii: Array[float] = []
		for vertex in base_vertices:
			radii.append(vertex.distance_to(stem_center))
		radii.sort()
		stem_radius = clampf(radii[radii.size() / 2] * 1.5, 0.12, 0.4)
	var capsule := CapsuleShape3D.new()
	capsule.radius = stem_radius
	capsule.height = maxf(minf(bounds.size.y * 0.9, 4.0), stem_radius * 2.0)
	var body := _new_body(mesh_instance, "Trunk")
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	shape_node.shape = capsule
	shape_node.position = Vector3(stem_center.x, bounds.position.y + capsule.height * 0.5, stem_center.y)
	body.add_child(shape_node)
	shape_node.owner = mesh_instance.owner
	return true


func _add_convex_collider(mesh_instance: MeshInstance3D, category: String) -> bool:
	var shape := mesh_instance.mesh.create_convex_shape()
	if shape == null:
		return false
	var body := _new_body(mesh_instance, category.capitalize())
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	shape_node.shape = shape
	body.add_child(shape_node)
	shape_node.owner = mesh_instance.owner
	return true


func _new_body(parent: Node3D, label: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = GENERATED_PREFIX + label
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	body.owner = parent.owner
	return body


func _remove_generated_colliders(node: Node) -> void:
	for child in node.get_children():
		if child is StaticBody3D and str(child.name).begins_with(GENERATED_PREFIX):
			node.remove_child(child)
			child.free()
		else:
			_remove_generated_colliders(child)


func _remove_foliage_collisions(asset_root: Node) -> int:
	var removed := 0
	for asset in asset_root.get_children():
		if not _is_excluded(str(asset.name).to_lower()):
			continue
		removed += _remove_existing_collision_bodies(asset)
	return removed


func _remove_existing_collision_bodies(node: Node) -> int:
	var removed := 0
	for child in node.get_children():
		if child is StaticBody3D:
			# Some imported foliage already had a trimesh collider. Remove those
			# too, so excluded leaves and grass cannot block the player.
			node.remove_child(child)
			child.free()
			removed += 1
		else:
			removed += _remove_existing_collision_bodies(child)
	return removed
