# PlayerController.gd
# This script handles both local and remote player movement, including physics, camera, and networking

extends CharacterBody3D

# ===== EXPORTED SETTINGS =====
@export_category("Movement Settings")
@export var walk_speed := 5.0          # Normal movement speed
@export var sprint_speed := 8.0        # Sprinting speed
@export var jump_velocity := 12.0      # Jump force
@export var ground_acceleration := 15.0 # Acceleration on ground
@export var ground_deceleration := 20.0 # Deceleration on ground
@export var air_control := 0.3         # Air movement control factor
@export var character_turn_speed := 12.0 # How quickly the visible character faces movement
@export var character_facing_yaw: float = PI # Replicated visual facing, relative to the player root

@export_category("Camera Settings")
@export var mouse_sensitivity := 0.01 # Mouse sensitivity
@export var controller_sensitivity := 3.0 # Controller stick look sensitivity (rad/s)
@export var camera_tilt_amount := 8.0  # Amount of camera tilt when strafing
@export var fov_normal := 80.0         # Normal field of view
@export var fov_sprint := 120.0        # Sprinting field of view
@export var sway_smoothness := 10.0    # Camera sway smoothing

@export_category("Network Settings")
@export var network_update_rate := 20.0 # Network updates per second
@export var interpolation_time := 0.15  # Network interpolation smoothing time

@export_category("Tarot Settings")
@export var tarot_capacity: int = 2     # Max tarot cards this player can carry

# ===== CONSTANTS =====
const GRAVITY_FORCE = 35.0            # Gravity strength
const POSITION_LERP_FACTOR = 0.3      # Position interpolation factor
const ROTATION_LERP_FACTOR = 0.5      # Rotation interpolation factor

# ===== NODE REFERENCES =====
@onready var camera := $Camera3D # Player camera
var pitch = 0.0 
@onready var head_position := $Camera3D/HeadPosition  # Hold point for picked-up objects
@onready var sync := $MultiplayerSynchronizer # Network sync component
@onready var effect_controller: TarotEffectController = $TarotEffectController #Effect controller component
@onready var interact_prompt: Label = $InteractPrompt/PromptLabel  # Interaction prompt label
@onready var animation_controller: Node = $AnimationController # Animation controller for character animations
@onready var flashlight : SpotLight3D = $Camera3D/Flashlight

# ===== MOVEMENT STATE =====
enum MovementState { WALKING, SPRINTING, AIRBORNE }
var current_state = MovementState.WALKING
var is_moving := false                # Whether player is moving
var wish_dir := Vector3.ZERO          # Desired movement direction
var current_speed := 0.0              # Current movement speed
var was_on_floor := true              # Previous frame ground state
var speed_modifier: float = 1.0 # Used while using demon speed
var input_multiplier: float  = 1.0 # Used for inverting the controls while using hanged man 
var knockback_velocity: Vector3 = Vector3.ZERO
var knockback_time_remaining: float = 0.0

# ===== JUMP VARIABLES =====
var jump_buffer_timer := 0.0          # Jump input buffer timer
var coyote_timer := 0.0               # Coyote time timer
var can_jump := true                  # Can player jump
var jump_count := 0                   # Current jump count
var jump_animation_name: StringName = &"jump_in_place"

# ===== CAMERA EFFECTS =====
var camera_tilt := 0.0                # Current camera tilt amount
var raw_input_dir := Vector2.ZERO     # Raw input direction
var vision_modifier: float  = 1.0
var render_distance_modifier: float = 1.0
@export var normal_render_distance: float  = 100.0 
var dark_moon_environment: Environment

# ===== NETWORK INTERPOLATION =====
var network_position_buffer = []      # Buffer for network positions
var network_rotation_buffer = []      # Buffer for network rotations
var network_timestamp_buffer = []     # Buffer for network timestamps
var last_network_update_time := 0.0   # Last network update time
var input_enabled: bool = true        # Whether input is enabled

## Body parts use this to identify their owner. Matches the network peer ID
## for the local player, and -1 for any player that has no authority.
var player_id: int = -1

# ===== LOOK-AT DETECTION =====
var look_at_ray: RayCast3D            # Raycast for detecting objects in front of player
var held_object: Node3D = null        # Currently held interactable object
var held_body_part: BodyPart = null   # Body part being carried, deposited at the spell center
var hovered_body_part: BodyPart = null # Body part which is being hovered


var _t := 0.0


func flicker_lights(delta) -> void:
	# Calls hotel.set_light() on a stuttery pattern.
	var hotel := get_node("/root/GameMode/SubViewportContainer/SubViewport/WorldObjects/hotel_map")
	_t -= delta
	if _t > 0.0:
		return
	_t = randf_range(0.03, 0.12) if hotel.is_light_on() else randf_range(0.05, 0.4)
	hotel.set_light(not hotel.is_light_on())
	
# Called every frame. Checks what the player is looking at and updates interaction prompt.
func _process(delta):
	# Update controller camera look (local player only)
	if is_multiplayer_authority() and input_enabled:
		process_controller_look(delta)

	# Hover identification is local to this player
	if not is_multiplayer_authority():
		return

	var current_hovered_part: BodyPart = null

	if look_at_ray and look_at_ray.is_colliding() and not held_object and not held_body_part:
		var hit_node = look_at_ray.get_collider()

		if hit_node is BodyPart:
			current_hovered_part = hit_node

		# Preserve the existing interaction prompt behavior
		if interact_prompt:
			interact_prompt.visible = hit_node != null and (
				hit_node.is_in_group("interactable")
				or hit_node is BodyPart
				or hit_node is TarotPickup
			)
	else:
		if interact_prompt:
			interact_prompt.visible = false

	# Hide the previously hovered body part
	if hovered_body_part != current_hovered_part:
		if is_instance_valid(hovered_body_part):
			hovered_body_part.set_owner_label_visible(false)

		hovered_body_part = current_hovered_part

	# Show the label on the newly hovered body part
	if is_instance_valid(hovered_body_part):
		hovered_body_part.set_owner_label_visible(true)

func process_controller_look(delta: float) -> void:
	var look_dir = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look_dir.length_squared() > 0.001:
		rotate_y(-look_dir.x * controller_sensitivity * delta)
		if camera:
			pitch = clamp(pitch - look_dir.y * controller_sensitivity * delta, deg_to_rad(-89), deg_to_rad(89))
			camera.rotation.x = pitch

func _enter_tree():
	# Set multiplayer authority based on name
	if name.contains("_"):
		var peer_id = name.get_slice("_", 1).to_int()
		set_multiplayer_authority(peer_id)
		player_id = peer_id
		if sync:
			sync.set_multiplayer_authority(peer_id)
			sync.replication_interval = 1.0 / network_update_rate
			sync.replication_config.add_property("global_position")
			sync.replication_config.add_property("rotation")
			sync.replication_config.add_property("velocity")

func _ready():
	add_to_group("player")
	print("Player Spawns at: ", global_position)
	dark_moon_environment = Environment.new()
	dark_moon_environment.background_mode = Environment.BG_COLOR
	dark_moon_environment.background_color = Color.BLACK
	# Setup for local player
	if is_multiplayer_authority():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if camera: 
			camera.far = normal_render_distance
			camera.current = true
		if interact_prompt:
			interact_prompt.text = "Press [X] to interact"
		var settings_node = get_node_or_null("/root/Settings")
		if settings_node and "settings" in settings_node:
			mouse_sensitivity = settings_node.settings.get("mouse_sensitivity", 0.002)
			controller_sensitivity = settings_node.settings.get("controller_sensitivity", 3.0)
	current_speed = walk_speed
	tarot_cards.resize(tarot_capacity)
	
	# Set up look-at raycast as child of camera
	look_at_ray = RayCast3D.new()
	look_at_ray.name = "LookAtDetector"
	look_at_ray.enabled = true
	look_at_ray.collide_with_areas = true
	look_at_ray.collision_mask = 1 | 8  # Layer 1 (interactables) + Layer 4 (BodyParts)
	look_at_ray.target_position = Vector3(0, 0, -10)  # 10 units forward
	look_at_ray.add_exception(self)
	if camera:
		camera.add_child(look_at_ray)
		
	GameManager.player_eliminated.connect(_on_player_eliminated)

	# Initialize animations
	if animation_controller and animation_controller.has_method("setup"):
		animation_controller.setup(self)

# ===== INPUT HANDLING =====
func _input(event):
	if not input_enabled or not is_multiplayer_authority():
		return
	
	# Mouse look
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		if camera:
			pitch = clamp(pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-89), deg_to_rad(89))
			camera.rotation.x = pitch
	
	# Jump input buffering
	if event.is_action_pressed("jump"):
		jump_buffer_timer = 0.15

	# Interact input
	if event.is_action_pressed("interact"):
		print("[Player] Interact triggered. held_object: ", held_object != null, ", held_body_part: ", held_body_part != null)
		if held_object:
			drop_object.rpc() ##TODO: Add Validation Checks here
		elif held_body_part:
			drop_body_part.rpc()
		elif look_at_ray and look_at_ray.is_colliding():
			var hit_node = look_at_ray.get_collider()
			print("[Player] Ray hit: ", hit_node.name if hit_node else "null", " (", hit_node.get_class() if hit_node else "null", ")")
			if hit_node == null:
				return
			if hit_node is TarotPickup:
				hit_node.collect.rpc(self.get_path())
			elif hit_node is BodyPart:
				pick_up_body_part.rpc(hit_node.get_path())
			elif hit_node.is_in_group("interactable"):
				request_pick_up.rpc_id(1, hit_node.get_path())
		else:
			print("[Player] Ray is not colliding with any object in range")
	
	# Tarot slots
	if event.is_action_pressed("tarot_slot_1"):
		use_tarot_card.rpc(0)
	elif event.is_action_pressed("tarot_slot_2"):
		use_tarot_card.rpc(1)
		
	if event.is_action_pressed("flashlight"):
		set_flashlight.rpc(not flashlight.visible)
		
# ===== Flashlight =====
@rpc("authority", "reliable", "call_local")
func set_flashlight(on : bool):
	flashlight.visible = on

# ===== TAROT INVENTORY =====
signal tarot_card_added(card: TarotCard, slot: int)  # Emitted when a card fills a slot
signal tarot_card_removed(slot: int)

var tarot_cards: Array[TarotCard] = []  # Fixed-size slots, empty slots hold null

# Stores a card in the first empty slot. Returns true if it fit.

@rpc("any_peer", "call_local", "reliable")
func add_tarot_card(card: TarotCard) -> bool:
	if card == null:
		push_warning("Cannot add a null Tarot card.")
		return false

	for i in range(tarot_cards.size()):
		if tarot_cards[i] == null:
			tarot_cards[i] = card
			print("Picked up Tarot Card: ", card.card_name, " | Slot: ", i)
			tarot_card_added.emit(card, i)
			return true

	print("Tarot inventory full.")
	return false

@rpc("any_peer", "call_local", "reliable")
func use_tarot_card(slot_index: int)->void:
	if slot_index < 0 or slot_index >= tarot_cards.size():
		push_warning("Invalid Tarot Card slot: "+str(slot_index))
		return
	
	var card: TarotCard = tarot_cards[slot_index]
	
	if card == null:
		push_warning("Tarot slot is empty: "+str(slot_index))
		return
	
	if card.effect == null:
		push_warning("Tarot card has no effect: "+card.card_name)
		return
	
	print("Using Tarot card ",card.card_name)
	
	var applied: bool = effect_controller.apply_effect(card.effect)
	
	if not applied:
		print("Could not apply Tarot Card: ",card.card_name)
		return
	
	tarot_cards[slot_index] = null
	tarot_card_removed.emit(slot_index)
	print("removed tarot cards : ",card.card_name," | Inventory: ",tarot_cards.size(),"/",tarot_capacity)

@rpc("any_peer", "call_remote", "reliable")
func teleport_to(new_position: Vector3) -> void:
	var sender_id := multiplayer.get_remote_sender_id()

	if multiplayer.is_server():
		if sender_id != 0:
			return
	else:
		if sender_id != 1:
			return

	global_position = new_position
	velocity = Vector3.ZERO
	print("Teleported ", name, " to ", new_position)

func _apply_tower_knockback_local(
	direction: Vector3,
	strength: float,
	duration: float
) -> void:
	if not is_multiplayer_authority():
		return

	knockback_velocity = direction.normalized() * strength
	knockback_time_remaining = duration

	if held_body_part != null:
		drop_body_part.rpc()

	print("Tower knockback applied to ", name)


@rpc("any_peer", "call_remote", "reliable")
func apply_tower_knockback(
	direction: Vector3,
	strength: float,
	duration: float
) -> void:
	var sender_id := multiplayer.get_remote_sender_id()

	# Only the server (peer ID 1) can trigger knockback.
	if sender_id != 1:
		return

	_apply_tower_knockback_local(direction, strength, duration)


func apply_speed_modifier(multiplier: float)->void:
	speed_modifier *= multiplier
	
	print("Speed modifier applied: ",multiplier," | current modifier  : ",speed_modifier)

func remove_speed_modifier(multiplier: float)->void:
	if multiplier == 0.0:
		return
	speed_modifier /= multiplier
	
	print("speed modifier removed : ",multiplier , " | current modifier : ",speed_modifier)

func apply_vision_modifier(multiplier: float)->void:
	vision_modifier *= multiplier
	camera.environment = dark_moon_environment
	print("vison modifier applied : ",multiplier, " | current modifier ",vision_modifier)

func remove_vision_modifier(multiplier: float)->void:
	if multiplier == 0.0:
		return 
	vision_modifier /= multiplier
	print("vison modifier removed : ",multiplier, " | current modifier ",vision_modifier)
	if is_equal_approx(vision_modifier,1.0):
		print("Restoring camera environment: null ")
		camera.environment = null

func apply_render_distance_modifier(multiplier: float)->void:
	render_distance_modifier *= multiplier
	camera.far = normal_render_distance*render_distance_modifier
	
	print("Render distance modifier applied : ",multiplier," | Far : ",camera.far)

func remove_render_distance_modifier(multiplier: float)->void:
	if multiplier == 0.0:
		return
	render_distance_modifier /= multiplier
	camera.far = normal_render_distance
	
	print("render distance modifer removed : ",multiplier," | Far : ",camera.far)

func apply_input_modifier(multiplier:float)->void:
	input_multiplier  *= multiplier
	print("Input modifier applied ",multiplier," | current modifier : ",input_multiplier)

func remove_input_modifier(multiplier: float)->void:
	if multiplier == 0.0:
		return
	input_multiplier /= multiplier
	print("Input modifier removed ",multiplier," | current modifier : ",input_multiplier)

# ===== PICKUP / DROP =====
@rpc("any_peer", "call_local", "reliable")
func request_pick_up(target: NodePath) -> void:
	if not multiplayer.is_server():
		return

	if target.is_empty():
		print("Empty Node Path!")
		return

	var id = multiplayer.get_remote_sender_id();
	##Adjust for Host Calling the Function
	if id == 0:
		id = 1;

	##Verify request from the Same Player
	if id != player_id:
		return

	##Check if Player is already holding an object
	if held_object != null:
		return

	##Check if that object exists or is not held by someone else
	if get_node_or_null(target) == null:
		return

	pick_up_object.rpc(target)

@rpc("any_peer", "call_local", "reliable")
func pick_up_object(targetPath: NodePath) -> void:
	if multiplayer.get_remote_sender_id() != 1 && multiplayer.get_remote_sender_id() != 0:
		return
	
	var target = get_node_or_null(targetPath)
	if target == null:
		print("NULL Target")
		return

	held_object = target
	if target is CSGBox3D:
		target.use_collision = false

	target.reparent(head_position, true)
	target.position = Vector3(0, 0, -2)
	print("Picked up: ", target.name)

@rpc("any_peer", "call_local", "reliable")
func drop_object() -> void:
	if not held_object:
		return
	if held_object is CSGBox3D:
		held_object.use_collision = true
	held_object.reparent(get_parent(), true)
	held_object = null
	print("Dropped object")

# ===== BODY PART CARRY =====
# Carries a body part to the spell center. No buffs, progress or removal
# happen here; that all waits for deposit_body_part().

@rpc("any_peer", "call_local", "reliable")
func pick_up_body_part(partPath : NodePath) -> void:
	var part := get_node_or_null(partPath)
	if part == null:
		print("Part is NULL! FAILED")
		return
		
	if part.owner_id == player_id:
		print("You cant pick up your own parts!")
		return

	if held_body_part != null or held_object != null:
		print("[Player] pick_up_body_part aborted: hands full")
		return
	if part.is_collected or part.is_carried:
		print("[Player] pick_up_body_part aborted: part already collected or carried")
		return

	held_body_part = part
	part.set_carried(true)
	part.reparent(head_position, true)
	part.position = Vector3(0, 0, -2)
	part.part_collected.connect(_on_part_collected)
	print("[Player] SUCCESS: Carrying body part: ", part.name)

# Called by the spell center. Hands the part to BodyPart.collect(), which is
# where progress, buffs and removal finally happen.

@rpc("any_peer", "call_local", "reliable")
func deposit_body_part() -> void:
	
	if held_body_part == null:
		print("[Player] deposit_body_part aborted: held_body_part is null")
		return

	print("[Player] Calling held_body_part.collect() for: ", held_body_part.name)
	held_body_part.set_carried(false)
	held_body_part.collect(self)
	held_body_part = null
	print("[Player] SUCCESS: Deposited body part")

# Returns a carried part to the world without collecting it.
@rpc("any_peer", "call_local", "reliable")
func drop_body_part() -> void:
	if not held_body_part:
		return

	held_body_part.set_carried(false)
	held_body_part.part_collected.disconnect(_on_part_collected)
	held_body_part.reparent(get_parent(), true)
	held_body_part = null
	print("Dropped body part")

# Clears the held reference if the part is collected by any other means.
func _on_part_collected(_collector: Node, _owner_id: int, _part_type: int) -> void:
	held_body_part = null

# ===== PHYSICS PROCESS =====
func _physics_process(delta):
	if not input_enabled:
		velocity = Vector3.ZERO
		return
		
	if is_multiplayer_authority():
		# Local player movement
		process_local_movement(delta)
		move_and_slide()
		update_character_facing(delta)
		send_network_update()
		update_camera_effects(delta)
	else:
		# Remote player movement interpolation
		process_remote_movement(delta)
		update_remote_character_facing(delta)

# ===== LOCAL MOVEMENT =====
func process_local_movement(delta):
	# Get input direction
	raw_input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")*input_multiplier
	is_moving = raw_input_dir.length() > 0.1
	wish_dir = (transform.basis * Vector3(raw_input_dir.x, 0, raw_input_dir.y)).normalized()
	
	# Handle jumping
	handle_jump_mechanics(delta)
	
	# Update movement state
	update_movement_state()
	
	# Calculate movement
	handle_movement(delta)
	
	# Apply gravity
	apply_gravity(delta)

# ===== JUMP MECHANICS =====
func handle_jump_mechanics(delta):
	# Update timers
	jump_buffer_timer = max(jump_buffer_timer - delta, 0)
	
	# Coyote time - allows jumping shortly after leaving ground
	if is_on_floor():
		coyote_timer = 0.1
		if not was_on_floor:
			can_jump = true
			jump_count = 0
	else:
		coyote_timer = max(coyote_timer - delta, 0)
	
	was_on_floor = is_on_floor()
	
	# Perform jump if conditions met
	if jump_buffer_timer > 0 and can_jump and (is_on_floor() or coyote_timer > 0):
		perform_jump()

func perform_jump():
	# Use the same in-place jump for standing, walking, and running jumps.
	jump_animation_name = &"jump_in_place"
	velocity.y = jump_velocity
	jump_buffer_timer = 0
	can_jump = false
	coyote_timer = 0
	jump_count += 1

# ===== MOVEMENT STATES =====
func update_movement_state():
	if is_on_floor():
		if Input.is_action_pressed("sprint") and is_moving and raw_input_dir.y < 0:
			current_state = MovementState.SPRINTING
			current_speed = sprint_speed*speed_modifier
		else:
			current_state = MovementState.WALKING
			current_speed = walk_speed*speed_modifier
	else:
		current_state = MovementState.AIRBORNE

	_play_movement_animation()

func _play_movement_animation() -> void:
	if not animation_controller or not animation_controller.has_method("play_walk"):
		return
	var locomotion_animation: StringName = &""
	match current_state:
		MovementState.WALKING:
			if not is_moving:
				animation_controller.play_idle()
				return
			if Input.is_action_pressed("crouch"):
				locomotion_animation = &"crouch_walk"
			elif absf(raw_input_dir.x) > absf(raw_input_dir.y) + 0.1:
				locomotion_animation = &"strafe_left" if raw_input_dir.x < 0.0 else &"strafe_right"
			elif raw_input_dir.y > 0.1:
				locomotion_animation = &"walk_back"
			else:
				locomotion_animation = &"walk"
		MovementState.SPRINTING:
			locomotion_animation = &"run"
		MovementState.AIRBORNE:
			if velocity.y > 0:
				animation_controller.play_jump(jump_animation_name)
			elif animation_controller.has_method("is_jump_animation_playing") and animation_controller.is_jump_animation_playing():
				# Let the selected jump clip finish through the descending part.
				pass
			else:
				animation_controller.play_fall()
			return

	if animation_controller.has_method("play_state"):
		animation_controller.play_state(locomotion_animation)

# ===== MOVEMENT CALCULATION =====
func handle_movement(delta):
	if is_on_floor():
		# Ground movement
		var current_vel = Vector2(velocity.x, velocity.z)
		var target_vel = Vector2(wish_dir.x, wish_dir.z) * current_speed
		
		if wish_dir.length() > 0:
			current_vel = current_vel.move_toward(target_vel, ground_acceleration * delta)
		else:
			current_vel = current_vel.move_toward(Vector2.ZERO, ground_deceleration * delta)
		
		velocity.x = current_vel.x
		velocity.z = current_vel.y
	else:
		# Air movement
		var current_vel = Vector2(velocity.x, velocity.z)
		var target_vel = Vector2(wish_dir.x, wish_dir.z) * current_speed
		
		if wish_dir.length() > 0:
			current_vel = current_vel.move_toward(target_vel, ground_acceleration * air_control * delta)
			velocity.x = current_vel.x
			velocity.z = current_vel.y
	if knockback_time_remaining > 0.0:
		velocity.x = knockback_velocity.x
		velocity.z = knockback_velocity.z

		knockback_time_remaining -= delta
		knockback_velocity = knockback_velocity.move_toward(
			Vector3.ZERO, 20.0 * delta
		)
	else:
		knockback_velocity = Vector3.ZERO

func apply_gravity(delta):
	if not is_on_floor():
		velocity.y -= GRAVITY_FORCE * delta

# ===== CAMERA EFFECTS =====
func update_camera_effects(delta):
	if not camera: return
	
	# Camera tilt when strafing
	var target_tilt = 0.0
	if is_moving and is_on_floor():
		target_tilt = -raw_input_dir.x * camera_tilt_amount
	
	camera_tilt = lerp(camera_tilt, target_tilt, delta * sway_smoothness)
	camera.rotation.z = deg_to_rad(camera_tilt)
	
	# FOV changes when sprinting
	var target_fov := fov_normal
	if current_state == MovementState.SPRINTING and raw_input_dir.y < 0:
		target_fov = fov_sprint
	
	target_fov *= vision_modifier
	
	camera.fov = lerp(camera.fov,target_fov,delta*5.0)

# ===== NETWORK UPDATES =====
func send_network_update():
	# Send position/rotation update to other players
	rpc("_receive_network_update", 
		global_position,
		velocity,
		rotation,
		Time.get_ticks_msec() / 1000.0)

@rpc("unreliable_ordered", "any_peer")
func _receive_network_update(pos: Vector3, vel: Vector3, rot: Vector3, timestamp: float):
	if is_multiplayer_authority(): return
	
	# Store update for interpolation
	network_position_buffer.append(pos)
	network_rotation_buffer.append(rot)
	network_timestamp_buffer.append(timestamp)
	
	# Maintain buffer size
	if network_position_buffer.size() > 5:
		network_position_buffer.pop_front()
		network_rotation_buffer.pop_front()
		network_timestamp_buffer.pop_front()
	
	last_network_update_time = Time.get_ticks_msec() / 1000.0

# ===== REMOTE PLAYER INTERPOLATION =====
func process_remote_movement(delta):
	if network_position_buffer.size() < 2: 
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var render_time = current_time - interpolation_time
	
	# Find closest states for interpolation
	var prev_index = -1
	var next_index = -1
	
	for i in range(network_timestamp_buffer.size()):
		if network_timestamp_buffer[i] <= render_time:
			prev_index = i
		else:
			next_index = i
			break
	
	if next_index == -1:
		if network_timestamp_buffer.size() < 2: return
		prev_index = network_timestamp_buffer.size() - 2
		next_index = network_timestamp_buffer.size() - 1
	elif prev_index == -1:
		prev_index = 0
		next_index = 1
	
	# Calculate interpolation factor
	var prev_time = network_timestamp_buffer[prev_index]
	var next_time = network_timestamp_buffer[next_index]
	var t = clamp((render_time - prev_time) / (next_time - prev_time), 0.0, 1.0)
	
	# Interpolate position and rotation
	var target_pos = network_position_buffer[prev_index].lerp(
		network_position_buffer[next_index], t)
	var target_rot = network_rotation_buffer[prev_index].lerp(
		network_rotation_buffer[next_index], t)
	
	# Apply with smoothing
	global_position = global_position.lerp(target_pos, POSITION_LERP_FACTOR)
	rotation = rotation.lerp(target_rot, ROTATION_LERP_FACTOR)

func update_character_facing(delta: float) -> void:
	var model := animation_controller.character_node as Node3D if animation_controller else null
	if not is_instance_valid(model):
		return

	var travel_direction := Vector3(velocity.x, 0.0, velocity.z)
	if travel_direction.length_squared() < 0.04:
		return

	var local_direction := global_transform.basis.inverse() * travel_direction.normalized()
	var desired_facing_yaw: float
	if current_state == MovementState.WALKING \
		and not Input.is_action_pressed("crouch") \
		and absf(raw_input_dir.x) > absf(raw_input_dir.y) + 0.1:
		# Aim the selected strafe side (the arm at 3 or 9 o'clock) into travel.
		if raw_input_dir.x > 0.0:
			desired_facing_yaw = atan2(local_direction.z, -local_direction.x)
		else:
			desired_facing_yaw = atan2(-local_direction.z, local_direction.x)
	elif current_state == MovementState.WALKING \
		and not Input.is_action_pressed("crouch") \
		and raw_input_dir.y > 0.1:
		# Back-walk travels in the direction of the character's back (6 o'clock).
		desired_facing_yaw = atan2(-local_direction.x, -local_direction.z)
	else:
		# Forward walk, run, crouch-walk, and forward jump travel from the front.
		desired_facing_yaw = atan2(local_direction.x, local_direction.z)

	character_facing_yaw = desired_facing_yaw
	var turn_weight := 1.0 - exp(-character_turn_speed * delta)
	model.rotation.y = lerp_angle(model.rotation.y, character_facing_yaw, turn_weight)

func update_remote_character_facing(delta: float) -> void:
	var model := animation_controller.character_node as Node3D if animation_controller else null
	if not is_instance_valid(model):
		return
	var turn_weight := 1.0 - exp(-character_turn_speed * delta)
	model.rotation.y = lerp_angle(model.rotation.y, character_facing_yaw, turn_weight)

# ===== INPUT CONTROL =====
func set_input_enabled(enabled: bool):
	input_enabled = enabled
	if is_multiplayer_authority():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE)
		

# Hanlde Player Elimination
func _on_player_eliminated(peer_id : int, name : String) -> void:
	if peer_id != player_id:
		return
	set_input_enabled(false)
	collision_layer = 0
	collision_mask = 0
	hide()
	
