extends Resource
class_name CharacterDefinition

## Data for one playable character model. A future selector can present these
## definitions and pass the chosen resource to PlayerAnimationController.
@export var character_id: StringName
@export var display_name: String
@export var model_scene: PackedScene
@export var vertical_offset: float = -1.1
@export var model_scale: Vector3 = Vector3.ONE
