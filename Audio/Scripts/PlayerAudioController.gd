class_name PlayerAudioController
extends Node3D

## Non-invasive audio controller for Player characters.
## Monitors parent player movement, jump, landing, flashlight, and item interactions
## without altering or interfering with any teammate codebase.

# Audio Streams
var DIRT_STEPS: Array[AudioStream] = []
var WOOD_STEPS: Array[AudioStream] = []
var MUD_STEPS: Array[AudioStream] = []

var SND_JUMP_TAKEOFF: AudioStream = null
var SND_JUMP_LAND_SOFT: AudioStream = null
var SND_JUMP_LAND_HARD: AudioStream = null
var SND_PLAYER_PUSH: AudioStream = null
var SND_TORCH_ON: AudioStream = null
var SND_TORCH_OFF: AudioStream = null
var SND_TORCH_FLICKER: AudioStream = null
var SND_FLESH_PICKUP: AudioStream = null
var SND_TAROT_DRAW: AudioStream = null
var SND_TAROT_ACTIVATE: AudioStream = null

# Audio Players
var footstep_player: AudioStreamPlayer3D = null
var action_player: AudioStreamPlayer3D = null
var torch_player: AudioStreamPlayer3D = null

# Parent player reference
var player: CharacterBody3D = null

# Movement & Footstep state
var step_accumulator: float = 0.0
var last_step_index: int = -1
var was_on_floor: bool = true
var max_downward_speed: float = 0.0

# Flashlight state
var flashlight: SpotLight3D = null
var flashlight_timer: Timer = null
var prev_flashlight_visible: bool = false
var flicker_played: bool = false

# Item & combat state
var prev_held_part: Node = null
var prev_knockback_time: float = 0.0

# Surface detection ray
var surface_ray: RayCast3D = null

func _load_sound(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	return null

func _init() -> void:
	# Instantiate players early
	footstep_player = AudioStreamPlayer3D.new()
	footstep_player.name = "FootstepAudio3D"
	footstep_player.max_distance = 32.0
	footstep_player.unit_size = 2.5
	footstep_player.position = Vector3(0, -0.9, 0)

	action_player = AudioStreamPlayer3D.new()
	action_player.name = "ActionAudio3D"
	action_player.max_distance = 36.0
	action_player.unit_size = 3.0

	torch_player = AudioStreamPlayer3D.new()
	torch_player.name = "TorchAudio3D"
	torch_player.max_distance = 25.0
	torch_player.unit_size = 2.0

	# Load footstep variations
	for i in range(1, 5):
		var s := _load_sound("res://Audio/SFX/Footsteps/footstep_dirt_%d.wav" % i)
		if s: DIRT_STEPS.append(s)

	for i in range(1, 4):
		var s := _load_sound("res://Audio/SFX/Footsteps/footstep_wood_%d.wav" % i)
		if s: WOOD_STEPS.append(s)

	for i in range(1, 3):
		var s := _load_sound("res://Audio/SFX/Footsteps/footstep_mud_%d.wav" % i)
		if s: MUD_STEPS.append(s)

	# Load action SFX
	SND_JUMP_TAKEOFF = _load_sound("res://Audio/SFX/Player/jump_takeoff.wav")
	SND_JUMP_LAND_SOFT = _load_sound("res://Audio/SFX/Player/jump_land_soft.wav")
	SND_JUMP_LAND_HARD = _load_sound("res://Audio/SFX/Player/jump_land_hard.wav")
	SND_PLAYER_PUSH = _load_sound("res://Audio/SFX/Player/player_push.wav")
	SND_TORCH_ON = _load_sound("res://Audio/SFX/Torch/torch_on.wav")
	SND_TORCH_OFF = _load_sound("res://Audio/SFX/Torch/torch_off.wav")
	SND_TORCH_FLICKER = _load_sound("res://Audio/SFX/Torch/torch_flicker.wav")
	SND_FLESH_PICKUP = _load_sound("res://Audio/SFX/Ritual/flesh_pickup.wav")
	SND_TAROT_DRAW = _load_sound("res://Audio/SFX/Ritual/tarot_draw.wav")
	SND_TAROT_ACTIVATE = _load_sound("res://Audio/SFX/Ritual/tarot_activate.wav")

func _enter_tree() -> void:
	player = get_parent() as CharacterBody3D

	if footstep_player and not footstep_player.is_inside_tree():
		footstep_player.bus = &"Footsteps" if AudioServer.get_bus_index(&"Footsteps") != -1 else &"Master"
		add_child(footstep_player)

	if action_player and not action_player.is_inside_tree():
		action_player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master"
		add_child(action_player)

	if torch_player and not torch_player.is_inside_tree():
		torch_player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master"
		add_child(torch_player)

func _ready() -> void:
	if player == null:
		player = get_parent() as CharacterBody3D

	if player == null:
		push_warning("PlayerAudioController: Parent is not CharacterBody3D.")
		set_physics_process(false)
		return

	# Surface detection ray
	surface_ray = RayCast3D.new()
	surface_ray.name = "SurfaceDetector"
	surface_ray.target_position = Vector3(0, -1.8, 0)
	surface_ray.collision_mask = 1
	add_child(surface_ray)

	# Locate flashlight
	var cam = player.get_node_or_null("Camera3D")
	if cam:
		flashlight = cam.get_node_or_null("Flashlight") as SpotLight3D
		if flashlight:
			prev_flashlight_visible = flashlight.visible
			flashlight_timer = flashlight.get_node_or_null("Timer") as Timer

	# Connect to tarot signals if exposed
	if player.has_signal("tarot_card_added"):
		player.tarot_card_added.connect(_on_tarot_card_added)
	if player.has_signal("tarot_card_removed"):
		player.tarot_card_removed.connect(_on_tarot_card_removed)

func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return

	_process_footsteps(delta)
	_process_jump_and_landing(delta)
	_process_flashlight()
	_process_body_part_pickup()
	_process_knockback()

func _process_footsteps(delta: float) -> void:
	var on_floor: bool = player.is_on_floor()
	var h_vel: Vector2 = Vector2(player.velocity.x, player.velocity.z)
	var speed: float = h_vel.length()

	if on_floor and speed > 0.4:
		# Determine movement cadence & volume
		var step_distance_threshold: float = 2.0
		var step_volume_db: float = 0.0

		var is_sprinting: bool = false
		if "current_state" in player and player.current_state == 1:
			is_sprinting = true
		elif speed > 11.5:
			is_sprinting = true

		var is_crouching: bool = false
		if player.is_multiplayer_authority() and Input.is_action_pressed("crouch"):
			is_crouching = true

		if is_sprinting:
			step_distance_threshold = 2.3
			step_volume_db = 2.0
		elif is_crouching:
			step_distance_threshold = 1.4
			step_volume_db = -7.0
		else:
			step_distance_threshold = 1.8
			step_volume_db = 0.0

		step_accumulator += speed * delta

		if step_accumulator >= step_distance_threshold:
			step_accumulator = 0.0
			_play_footstep(step_volume_db, is_sprinting, is_crouching)
	else:
		step_accumulator = min(step_accumulator, 1.2)

func _play_footstep(volume_offset: float, is_sprint: bool, is_crouch: bool) -> void:
	if footstep_player == null:
		return

	var surface_type := _detect_surface()
	var pool: Array[AudioStream] = DIRT_STEPS

	match surface_type:
		"wood":
			pool = WOOD_STEPS
		"mud":
			pool = MUD_STEPS
		_:
			pool = DIRT_STEPS

	if pool.is_empty():
		return

	# Choose non-repeating step sound
	var idx := randi() % pool.size()
	if pool.size() > 1 and idx == last_step_index:
		idx = (idx + 1) % pool.size()
	last_step_index = idx

	var stream = pool[idx]
	if stream == null:
		return
	footstep_player.stream = stream

	# Pitch variation
	var pitch := randf_range(0.93, 1.07)
	if is_sprint:
		pitch *= 1.05
	elif is_crouch:
		pitch *= 0.92

	footstep_player.pitch_scale = pitch
	footstep_player.volume_db = volume_offset + randf_range(-1.0, 1.0)
	if footstep_player.is_inside_tree():
		footstep_player.play()

func _detect_surface() -> String:
	if surface_ray and surface_ray.is_colliding():
		var col = surface_ray.get_collider()
		if col != null and col is Node:
			var n: String = String(col.name).to_lower()
			var p: String = str(col.get_path()).to_lower()
			if "wood" in n or "shack" in n or "church" in n or "garage" in n or "floor" in n or "bridge" in n:
				return "wood"
			if "wood" in p or "shack" in p or "church" in p or "garage" in p:
				return "wood"
			if "swamp" in n or "mud" in n or "water" in n or "island" in n:
				return "mud"
			if "swamp" in p or "mud" in p:
				return "mud"
	return "dirt"

func _process_jump_and_landing(delta: float) -> void:
	if player == null:
		player = get_parent() as CharacterBody3D
	if player == null:
		return

	var on_floor: bool = player.is_on_floor()

	# Jump takeoff detection
	if was_on_floor and not on_floor and player.velocity.y > 4.5:
		if SND_JUMP_TAKEOFF and action_player:
			action_player.stream = SND_JUMP_TAKEOFF
			action_player.pitch_scale = randf_range(0.95, 1.05)
			action_player.volume_db = -1.0
			if action_player.is_inside_tree():
				action_player.play()

	# Airborne downward speed tracking
	if not on_floor:
		if player.velocity.y < 0.0:
			max_downward_speed = max(max_downward_speed, -player.velocity.y)
	else:
		# Landing detection
		if not was_on_floor and max_downward_speed > 2.5:
			if max_downward_speed >= 13.0:
				if SND_JUMP_LAND_HARD and action_player:
					action_player.stream = SND_JUMP_LAND_HARD
					action_player.pitch_scale = randf_range(0.92, 1.02)
					action_player.volume_db = 2.0
					if action_player.is_inside_tree():
						action_player.play()
			else:
				if SND_JUMP_LAND_SOFT and action_player:
					action_player.stream = SND_JUMP_LAND_SOFT
					action_player.pitch_scale = randf_range(0.95, 1.05)
					action_player.volume_db = 0.0
					if action_player.is_inside_tree():
						action_player.play()
			max_downward_speed = 0.0

	was_on_floor = on_floor

func _process_flashlight() -> void:
	if flashlight == null:
		return

	var is_visible: bool = flashlight.visible

	if is_visible != prev_flashlight_visible:
		prev_flashlight_visible = is_visible
		var snd = SND_TORCH_ON if is_visible else SND_TORCH_OFF
		if snd and torch_player:
			torch_player.stream = snd
			torch_player.pitch_scale = randf_range(0.97, 1.03)
			torch_player.volume_db = 0.0
			if torch_player.is_inside_tree():
				torch_player.play()
		flicker_played = false

	# Battery dying warning flicker sound
	if is_visible and flashlight_timer and not flashlight_timer.is_stopped():
		if flashlight_timer.time_left < 2.4 and flashlight_timer.time_left > 0.3:
			if not flicker_played and SND_TORCH_FLICKER and torch_player:
				flicker_played = true
				torch_player.stream = SND_TORCH_FLICKER
				torch_player.volume_db = -2.0
				if torch_player.is_inside_tree():
					torch_player.play()

func _process_body_part_pickup() -> void:
	if "held_body_part" in player:
		var current_part = player.held_body_part
		if current_part != null and prev_held_part == null:
			if SND_FLESH_PICKUP and action_player:
				action_player.stream = SND_FLESH_PICKUP
				action_player.pitch_scale = randf_range(0.95, 1.05)
				action_player.volume_db = 2.0
				if action_player.is_inside_tree():
					action_player.play()
		prev_held_part = current_part

func _process_knockback() -> void:
	if "knockback_time_remaining" in player:
		var kt: float = player.knockback_time_remaining
		if kt > 0.0 and prev_knockback_time <= 0.0:
			if SND_PLAYER_PUSH and action_player:
				action_player.stream = SND_PLAYER_PUSH
				action_player.pitch_scale = randf_range(0.95, 1.05)
				action_player.volume_db = 1.0
				if action_player.is_inside_tree():
					action_player.play()
		prev_knockback_time = kt

func _on_tarot_card_added(_card: Resource, _slot: int) -> void:
	if SND_TAROT_DRAW and action_player:
		action_player.stream = SND_TAROT_DRAW
		action_player.pitch_scale = randf_range(0.98, 1.04)
		action_player.volume_db = 1.0
		if action_player.is_inside_tree():
			action_player.play()

func _on_tarot_card_removed(_slot: int) -> void:
	if SND_TAROT_ACTIVATE and action_player:
		action_player.stream = SND_TAROT_ACTIVATE
		action_player.pitch_scale = randf_range(0.96, 1.02)
		action_player.volume_db = 3.0
		if action_player.is_inside_tree():
			action_player.play()
