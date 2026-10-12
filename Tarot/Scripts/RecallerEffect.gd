class_name RecallerEffect
extends TarotEffect

func apply(target: Node) -> void:
	var tree := target.get_tree()

	if not tree.get_multiplayer().is_server():
		return

	var game_mode := tree.current_scene

	if game_mode == null or not game_mode.has_method("get_random_spawn_position"):
		push_warning("RecallerEffect: GameMode spawn system not found")
		return

	var new_position: Vector3 = game_mode.get_random_spawn_position()

	if target.has_method("teleport_to"):
		var authority_id := target.get_multiplayer_authority()
		var multiplayer_api := tree.get_multiplayer()

		if authority_id == multiplayer_api.get_unique_id():
			target.teleport_to(new_position)
		else:
			target.teleport_to.rpc_id(authority_id, new_position)

		print("Recaller: recalling ", target.name, " to ", new_position)
	else:
		push_warning("RecallerEffect: Target has no teleport_to() method")


func remove(_target: Node) -> void:
	pass
