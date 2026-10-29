@tool
extends Node3D

const TERRAIN_ASSETS_PATH := "res://Materials/main_map_terrain_assets.tres"


func _ready() -> void:
	var terrain := get_node_or_null("Terrain3D") as Terrain3D
	if terrain == null:
		return

	var terrain_assets := load(TERRAIN_ASSETS_PATH) as Terrain3DAssets
	if terrain_assets == null:
		push_error("Main map terrain assets could not be loaded.")
		return

	# Reattach the palette after Terrain3D initializes; otherwise this scene's
	# Terrain3D instance can start with an empty texture list and render white.
	terrain.assets = terrain_assets
	if terrain.material:
		# Terrain3D's editor diagnostic views replace the normal terrain shading
		# with monochrome visualizations. Keep the playable map in its regular
		# textured view when the scene is opened or run.
		terrain.material.show_checkered = false
		terrain.material.show_control_texture = false
		terrain.material.show_autoshader = false
		terrain.material.show_texture_height = false
		terrain.material.show_texture_normal = false
		terrain.material.show_texture_rough = false
		terrain.material.update()
