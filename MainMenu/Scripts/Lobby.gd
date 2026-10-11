# Lobby.gd
# Pre-match waiting room shown between the main menu and the game.
# The host waits here for players to join and starts the match;
# clients wait here until the host starts.

extends Control

@onready var title_label: Label = $Panel/VBoxContainer/Title
@onready var status_label: Label = $Panel/VBoxContainer/Status
@onready var count_label: Label = $Panel/VBoxContainer/PlayerCount
@onready var player_list: VBoxContainer = $Panel/VBoxContainer/PlayerList
@onready var start_btn: Button = $Panel/VBoxContainer/Buttons/Start
@onready var leave_btn: Button = $Panel/VBoxContainer/Buttons/Leave

var _dots_time := 0.0

# Called when the node enters the scene tree
func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	multiplayer.peer_connected.connect(_on_peers_changed)
	multiplayer.peer_disconnected.connect(_on_peers_changed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	start_btn.pressed.connect(_on_start_pressed)
	leave_btn.pressed.connect(_on_leave_pressed)

	var is_host := multiplayer.is_server()
	title_label.text = "Hosting Game" if is_host else "Joined Game"
	start_btn.visible = is_host
	leave_btn.text = "Cancel" if is_host else "Leave"

	_setup_focus_styling()
	if is_host:
		start_btn.grab_focus()
	else:
		leave_btn.grab_focus()

	_refresh()

# Animate the trailing dots on the status message
func _process(delta: float) -> void:
	_dots_time += delta
	var dots := ".".repeat(int(_dots_time * 2.0) % 4)
	var base := "Waiting for players to join" if multiplayer.is_server() else "Waiting for host to start the match"
	status_label.text = base + dots

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_leave_pressed()
		get_viewport().set_input_as_handled()

func _setup_focus_styling() -> void:
	var focus_box := StyleBoxFlat.new()
	focus_box.draw_center = false
	focus_box.set_border_width_all(2)
	focus_box.border_color = Color(1.0, 0.84, 0.0, 1.0)
	focus_box.set_corner_radius_all(4)
	start_btn.add_theme_stylebox_override("focus", focus_box)
	leave_btn.add_theme_stylebox_override("focus", focus_box)

func _on_peers_changed(_id: int) -> void:
	_refresh()

# Rebuild the player count and roster from the current set of connected peers
func _refresh() -> void:
	# With server relay (the default), every peer sees all other peers
	var ids: Array = [multiplayer.get_unique_id()]
	ids.append_array(multiplayer.get_peers())
	ids.sort()

	count_label.text = "Players joined: %d / %d" % [ids.size(), GameManager.MAX_PLAYERS]

	for child in player_list.get_children():
		child.queue_free()
	for i in ids.size():
		var id: int = ids[i]
		var entry := Label.new()
		entry.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		entry.text = "Player %d" % (i + 1)
		if id == 1:
			entry.text += " (Host)"
		if id == multiplayer.get_unique_id():
			entry.text += " - You"
		if i < GameManager.PLAYER_COLOR_VALUES.size():
			entry.modulate = GameManager.PLAYER_COLOR_VALUES[i].lightened(0.3)
		player_list.add_child(entry)

func _on_start_pressed() -> void:
	start_btn.disabled = true
	NetworkManager.start_game()

func _on_leave_pressed() -> void:
	NetworkManager.leave_session()

func _on_server_disconnected() -> void:
	print("Host closed the lobby")
	NetworkManager.leave_session()
