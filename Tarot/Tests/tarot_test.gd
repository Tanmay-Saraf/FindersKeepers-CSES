extends Node3D

func get_random_spawn_position() -> Vector3:
	var marker := get_node_or_null("Marker3D") as Marker3D

	if marker != null:
		return marker.global_position

	return Vector3(8, 0, 0)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
