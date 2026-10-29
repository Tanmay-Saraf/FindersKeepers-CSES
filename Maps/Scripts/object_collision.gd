extends MeshInstance3D

## Adds a static trimesh collider for imported map meshes that lack one.
func _ready() -> void:
	if mesh == null:
		return

	var body := StaticBody3D.new()
	body.name = "StaticBody3D"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
