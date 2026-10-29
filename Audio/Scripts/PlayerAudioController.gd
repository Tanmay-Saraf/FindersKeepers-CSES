class_name PlayerAudioController
extends Node3D

## Realistic, grounded audio controller for Player characters.
## Handles audible textured footsteps (Dirt, Wood, Mud), realistic human jump & landing
## (NO cartoon/Mario sweeps), flashlight toggles, and item interactions.
## Supports direct 2D presence for the local player and 3D spatialization for remote peers.

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
var SND_CHURCH_BELL: AudioStream = null

# 3D Audio Players (used for remote players so they can be heard in 3D around you)
var footstep_player_3d: AudioStreamPlayer3D = null
var action_player_3d: AudioStreamPlayer3D = null
var torch_player_3d: AudioStreamPlayer3D = null

# 2D Audio Players (used for the LOCAL player for clear, crisp, direct stereo presence)
var footstep_player_2d: AudioStreamPlayer = null
var action_player_2d: AudioStreamPlayer = null
var torch_player_2d: AudioStreamPlayer = null
var church_bell_player_2d: AudioStreamPlayer = null

# Church Bell State (Only plays when inside church)
var is_inside_church: bool = false
var church_bell_timer: float = 0.0

# Parent player reference
var player: CharacterBody3D = null
var is_local: bool = true

# Movement & Footstep state
var step_accumulator: float = 3.0 # Start charged so initial step triggers immediately
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
	# 3D Players (for remote players)
	footstep_player_3d = AudioStreamPlayer3D.new()
	footstep_player_3d.name = "FootstepAudio3D"
	footstep_player_3d.max_distance = 45.0
	footstep_player_3d.unit_size = 4.0
	footstep_player_3d.position = Vector3(0, -0.9, 0)

	action_player_3d = AudioStreamPlayer3D.new()
	action_player_3d.name = "ActionAudio3D"
	action_player_3d.max_distance = 50.0
	action_player_3d.unit_size = 4.5

	torch_player_3d = AudioStreamPlayer3D.new()
	torch_player_3d.name = "TorchAudio3D"
	torch_player_3d.max_distance = 35.0
	torch_player_3d.unit_size = 3.0

	# 2D Players (for local player direct crisp stereo)
	footstep_player_2d = AudioStreamPlayer.new()
	footstep_player_2d.name = "FootstepAudio2D"

	action_player_2d = AudioStreamPlayer.new()
	action_player_2d.name = "ActionAudio2D"

	torch_player_2d = AudioStreamPlayer.new()
	torch_player_2d.name = "TorchAudio2D"

	church_bell_player_2d = AudioStreamPlayer.new()
	church_bell_player_2d.name = "ChurchBellAudio2D"
	church_bell_player_2d.volume_db = -3.0

	# Load church bell clip
	SND_CHURCH_BELL = _load_sound("res://Audio/SFX/Church/church_bell_creepy.mp3")
	if SND_CHURCH_BELL:
		church_bell_player_2d.stream = SND_CHURCH_BELL

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

	var footsteps_bus: StringName = &"Footsteps" if AudioServer.get_bus_index(&"Footsteps") != -1 else &"Master"
	var sfx_bus: StringName = &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master"

	if footstep_player_3d and not footstep_player_3d.is_inside_tree():
		footstep_player_3d.bus = footsteps_bus
		add_child(footstep_player_3d)

	if action_player_3d and not action_player_3d.is_inside_tree():
		action_player_3d.bus = sfx_bus
		add_child(action_player_3d)

	if torch_player_3d and not torch_player_3d.is_inside_tree():
		torch_player_3d.bus = sfx_bus
		add_child(torch_player_3d)

	if footstep_player_2d and not footstep_player_2d.is_inside_tree():
		footstep_player_2d.bus = footsteps_bus
		add_child(footstep_player_2d)

	if action_player_2d and not action_player_2d.is_inside_tree():
		action_player_2d.bus = sfx_bus
		add_child(action_player_2d)

	if torch_player_2d and not torch_player_2d.is_inside_tree():
		torch_player_2d.bus = sfx_bus
		add_child(torch_player_2d)

	if church_bell_player_2d and not church_bell_player_2d.is_inside_tree():
		church_bell_player_2d.bus = &"Ambience" if AudioServer.get_bus_index(&"Ambience") != -1 else &"Master"
		add_child(church_bell_player_2d)

func _ready() -> void:
	if player == null:
		player = get_parent() as CharacterBody3D

	if player == null:
		push_warning("PlayerAudioController: Parent is not CharacterBody3D.")
		set_physics_process(false)
		return

	# Determine authority
	is_local = player.is_multiplayer_authority()

	# If local player, ensure camera has an active AudioListener3D so all 3D world sounds work
	if is_local:
		var cam = player.get_node_or_null("Camera3D")
		if cam:
			var listener = cam.get_node_or_null("AudioListener3D")
			if listener == null:
				listener = AudioListener3D.new()
				listener.name = "AudioListener3D"
				cam.add_child(listener)
				listener.make_current()

	# Surface detection ray
	surface_ray = RayCast3D.new()
	surface_ray.name = "SurfaceDetector"
	surface_ray.target_position = Vector3(0, -2.5, 0)
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

	is_local = player.is_multiplayer_authority()

	_process_footsteps(delta)
	_process_jump_and_landing(delta)
	_process_church_bell(delta)
	_process_flashlight()
	_process_body_part_pickup()
	_process_knockback()

func _process_footsteps(delta: float) -> void:
	var on_floor: bool = player.is_on_floor()
	var h_vel: Vector2 = Vector2(player.velocity.x, player.velocity.z)
	var speed: float = h_vel.length()
	var is_moving: bool = speed > 0.4 or (player.get("is_moving") != null and player.is_moving)

	if on_floor and is_moving:
		# Cadence tailored to match movement speeds (walk ~10, sprint ~15)
		var step_distance_threshold: float = 3.6
		var step_volume_db: float = 3.5

		var is_sprinting: bool = false
		if "current_state" in player and player.current_state == 1:
			is_sprinting = true
		elif speed > 11.5:
			is_sprinting = true

		var is_crouching: bool = false
		if is_local and Input.is_action_pressed("crouch"):
			is_crouching = true

		if is_sprinting:
			step_distance_threshold = 4.2 # Rapid heavy sprint steps (~3.5/sec)
			step_volume_db = 6.0
		elif is_crouching:
			step_distance_threshold = 2.4 # Deliberate stealth creep (~2.0/sec)
			step_volume_db = -1.0 # Clearly audible to the player, just softer
		else:
			step_distance_threshold = 3.6 # Natural walking cadence (~2.8/sec)
			step_volume_db = 3.5

		step_accumulator += speed * delta

		if step_accumulator >= step_distance_threshold:
			step_accumulator = 0.0
			_play_footstep(step_volume_db, is_sprinting, is_crouching)
	else:
		step_accumulator = min(step_accumulator, 2.5)

func _play_footstep(volume_offset: float, is_sprint: bool, is_crouch: bool) -> void:
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

	var stream: AudioStream = pool[idx]
	if stream == null:
		return

	# Pitch micro-variation (realistic human variation)
	var pitch := randf_range(0.95, 1.05)
	if is_sprint:
		pitch *= 1.04
	elif is_crouch:
		pitch *= 0.93

	var final_vol := volume_offset + randf_range(-0.8, 0.8)

	if is_local:
		if footstep_player_2d and footstep_player_2d.is_inside_tree():
			footstep_player_2d.stream = stream
			footstep_player_2d.pitch_scale = pitch
			footstep_player_2d.volume_db = final_vol
			footstep_player_2d.play()
	else:
		if footstep_player_3d and footstep_player_3d.is_inside_tree():
			footstep_player_3d.stream = stream
			footstep_player_3d.pitch_scale = pitch
			footstep_player_3d.volume_db = final_vol
			footstep_player_3d.play()

func _detect_surface() -> String:
	# Method 1: Check slide collision under feet
	if player and player.get_slide_collision_count() > 0:
		for i in range(player.get_slide_collision_count()):
			var col = player.get_slide_collision(i).get_collider()
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

	# Method 2: Raycast fallback
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

func _process_jump_and_landing(_delta: float) -> void:
	if player == null:
		player = get_parent() as CharacterBody3D
	if player == null:
		return

	var on_floor: bool = player.is_on_floor()

	# Jump takeoff detection (realistic body thrust, clothes rustle, human effort puff)
	if was_on_floor and not on_floor and player.velocity.y > 4.0:
		if SND_JUMP_TAKEOFF:
			_play_action_sound(SND_JUMP_TAKEOFF, 3.0, randf_range(0.96, 1.04))

	# Airborne downward speed tracking
	if not on_floor:
		if player.velocity.y < 0.0:
			max_downward_speed = max(max_downward_speed, -player.velocity.y)
	else:
		# Landing detection - jump landing sound completely removed per user request
		if not was_on_floor:
			max_downward_speed = 0.0

	was_on_floor = on_floor

func _check_inside_church() -> bool:
	if player == null:
		return false
	
	# Check 1: Slide collisions with church geometry / objects
	for i in range(player.get_slide_collision_count()):
		var col = player.get_slide_collision(i).get_collider()
		if col != null and col is Node:
			var n: String = String(col.name).to_lower()
			var p: String = str(col.get_path()).to_lower()
			if "church" in n or "church" in p or "staris" in n or "staris" in p or "chandelier" in n or "chandelier" in p:
				return true

	# Check 2: Surface raycast
	if surface_ray and surface_ray.is_colliding():
		var col = surface_ray.get_collider()
		if col != null and col is Node:
			var n: String = String(col.name).to_lower()
			var p: String = str(col.get_path()).to_lower()
			if "church" in n or "church" in p or "staris" in n or "staris" in p:
				return true

	# Check 3: World coordinates of Church in main_map / GameMode
	# Church is placed at Vector3(-109.32, 41.94, 28.42) with ~32m radius
	var church_pos = Vector3(-109.32, 41.94, 28.42)
	var player_pos = player.global_position
	var dx = player_pos.x - church_pos.x
	var dz = player_pos.z - church_pos.z
	var dy = abs(player_pos.y - church_pos.y)
	if (dx * dx + dz * dz) < 1024.0 and dy < 18.0: # 32m radius squared
		return true

	return false

func _process_church_bell(delta: float) -> void:
	if not is_local or SND_CHURCH_BELL == null or church_bell_player_2d == null:
		return

	var inside: bool = _check_inside_church()

	if inside:
		if not is_inside_church:
			is_inside_church = true
			# Player entered the church! Toll the creepy church bell!
			church_bell_player_2d.volume_db = -3.0
			church_bell_player_2d.pitch_scale = randf_range(0.97, 1.03)
			church_bell_player_2d.play()
			print("[PlayerAudioController] Entered church -> Tolling creepy church bell")
		else:
			# Player is still inside church. Re-toll every ~16 seconds if finished
			if not church_bell_player_2d.is_playing():
				church_bell_timer -= delta
				if church_bell_timer <= 0.0:
					church_bell_timer = randf_range(14.0, 20.0)
					church_bell_player_2d.pitch_scale = randf_range(0.96, 1.04)
					church_bell_player_2d.play()
			else:
				church_bell_timer = 5.0
	else:
		if is_inside_church:
			is_inside_church = false
			# Player left the church -> stop church bell
			if church_bell_player_2d.is_playing():
				church_bell_player_2d.stop()
				print("[PlayerAudioController] Exited church -> Stopped church bell")

func _play_action_sound(stream: AudioStream, vol_db: float, pitch: float) -> void:
	if stream == null:
		return
	if is_local:
		if action_player_2d and action_player_2d.is_inside_tree():
			action_player_2d.stream = stream
			action_player_2d.pitch_scale = pitch
			action_player_2d.volume_db = vol_db
			action_player_2d.play()
	else:
		if action_player_3d and action_player_3d.is_inside_tree():
			action_player_3d.stream = stream
			action_player_3d.pitch_scale = pitch
			action_player_3d.volume_db = vol_db
			action_player_3d.play()

func _process_flashlight() -> void:
	if flashlight == null:
		return

	var is_visible: bool = flashlight.visible

	if is_visible != prev_flashlight_visible:
		prev_flashlight_visible = is_visible
		var snd = SND_TORCH_ON if is_visible else SND_TORCH_OFF
		if snd:
			if is_local:
				if torch_player_2d and torch_player_2d.is_inside_tree():
					torch_player_2d.stream = snd
					torch_player_2d.pitch_scale = randf_range(0.97, 1.03)
					torch_player_2d.volume_db = 2.0
					torch_player_2d.play()
			else:
				if torch_player_3d and torch_player_3d.is_inside_tree():
					torch_player_3d.stream = snd
					torch_player_3d.pitch_scale = randf_range(0.97, 1.03)
					torch_player_3d.volume_db = 2.0
					torch_player_3d.play()
		flicker_played = false

	# Battery dying warning flicker sound
	if is_visible and flashlight_timer and not flashlight_timer.is_stopped():
		if flashlight_timer.time_left < 2.4 and flashlight_timer.time_left > 0.3:
			if not flicker_played and SND_TORCH_FLICKER:
				flicker_played = true
				if is_local and torch_player_2d and torch_player_2d.is_inside_tree():
					torch_player_2d.stream = SND_TORCH_FLICKER
					torch_player_2d.volume_db = 0.0
					torch_player_2d.play()
				elif torch_player_3d and torch_player_3d.is_inside_tree():
					torch_player_3d.stream = SND_TORCH_FLICKER
					torch_player_3d.volume_db = 0.0
					torch_player_3d.play()

func _process_body_part_pickup() -> void:
	if "held_body_part" in player:
		var current_part = player.held_body_part
		if current_part != null and prev_held_part == null:
			if SND_FLESH_PICKUP:
				_play_action_sound(SND_FLESH_PICKUP, 4.0, randf_range(0.95, 1.05))
		prev_held_part = current_part

func _process_knockback() -> void:
	if "knockback_time_remaining" in player:
		var kt: float = player.knockback_time_remaining
		if kt > 0.0 and prev_knockback_time <= 0.0:
			if SND_PLAYER_PUSH:
				_play_action_sound(SND_PLAYER_PUSH, 3.0, randf_range(0.95, 1.05))
		prev_knockback_time = kt

func _on_tarot_card_added(_card: Resource, _slot: int) -> void:
	if SND_TAROT_DRAW:
		_play_action_sound(SND_TAROT_DRAW, 2.5, randf_range(0.98, 1.04))

func _on_tarot_card_removed(_slot: int) -> void:
	if SND_TAROT_ACTIVATE:
		_play_action_sound(SND_TAROT_ACTIVATE, 4.5, randf_range(0.96, 1.02))
