extends TarotEffect
class_name TowerEffect

const TOWER_RADIUS: float = 8.0
const KNOCKBACK_STRENGTH: float = 14.0
const KNOCKBACK_DURATION: float = 0.45


func apply(target: Node) -> void:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return

	if not target is Node3D:
		return

	var scene_tree := target.get_tree()
	var multiplayer_api := scene_tree.get_multiplayer()

	if not multiplayer_api.is_server():
		return

	var caster: Node3D = target
	var players := scene_tree.get_nodes_in_group("player")
	var local_peer_id := multiplayer_api.get_unique_id()

	for player in players:
		if player == caster:
			continue

		if not player is CharacterBody3D:
			continue

		var distance := caster.global_position.distance_to(
			player.global_position
		)

		if distance > TOWER_RADIUS:
			continue

		var direction : Vector3 = (
			player.global_position - caster.global_position
		).normalized()

		if direction.length_squared() < 0.001:
			direction = Vector3.FORWARD

		var peer_id := player.get_multiplayer_authority()

		if peer_id == local_peer_id:
			player._apply_tower_knockback_local(
				direction,
				KNOCKBACK_STRENGTH,
				KNOCKBACK_DURATION
			)
		else:
			player.rpc_id(
				peer_id,
				"apply_tower_knockback",
				direction,
				KNOCKBACK_STRENGTH,
				KNOCKBACK_DURATION
			)

	print("Tower activated by ", caster.name)
