
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

	if not target.has_method("teleport_to"):
		push_warning("RecallerEffect: Target has no teleport_to() method")
		return

	var new_position: Vector3 = game_mode.get_random_spawn_position()

	# The server owns the teleport decision.
	# Send the teleport to the target player's authority.
	var authority_id: int = target.get_multiplayer_authority()

	if authority_id == 1:
		target.global_position = new_position
		target.velocity = Vector3.ZERO
	else:
		target.teleport_to.rpc_id(authority_id, new_position)

	print("Recaller: recalling ", target.name, " to ", new_position)

func remove(_target: Node) -> void:
	pass
