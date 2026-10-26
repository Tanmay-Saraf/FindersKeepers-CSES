# TarotInventoryUI.gd
# Displays the local player's tarot cards in the HUD slots.
# Read-only view of Player.tarot_cards; it never modifies the inventory.

extends Control

# Slot panels and their text labels, ordered left to right.
@onready var slot_panels: Array[Control] = [
	$HBoxContainer/Slot1,
	$HBoxContainer/Slot2,
]
@onready var slot_labels: Array[Label] = [
	$HBoxContainer/Slot1/Label,
	$HBoxContainer/Slot2/Label,
]

# Untyped so we can access the Player's tarot members dynamically.
var _player = null
var _slot_art: Array[TextureRect] = []

func _ready() -> void:
	for i in range(slot_panels.size()):
		var art := TextureRect.new()
		art.name = "CardArt"
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.modulate = Color(1, 1, 1, 0.72)
		slot_panels[i].add_child(art)
		slot_panels[i].move_child(art, 0)
		_slot_art.append(art)
		slot_labels[i].vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		slot_labels[i].add_theme_color_override("font_color", Color("fff3d5"))
		slot_labels[i].add_theme_color_override("font_shadow_color", Color(0.05, 0.02, 0.04, 0.95))
		slot_labels[i].add_theme_constant_override("shadow_offset_x", 1)
		slot_labels[i].add_theme_constant_override("shadow_offset_y", 2)
	_try_bind_local_player()

# Players are spawned by GameMode, and a node's _ready() runs before its
# parent's, so the local player does not exist yet when this runs. Retry
# until it shows up (this also covers players that join later).

func _process(_delta : float ) -> void:
	if is_instance_valid(_player):
		set_process(false)
		return
	_try_bind_local_player()

func _try_bind_local_player() -> void:
	if is_instance_valid(_player):
		return

	var scene := get_tree().current_scene
	var world: Node = scene.get("world") if scene != null else null
	if world == null:
		return

	for child in world.get_children():
		# has_method filters out the floor/pickups, which also report
		# authority 1 and would otherwise match on the host.
		if child.has_method("add_tarot_card") and child.is_multiplayer_authority():
			_player = child
			_player.tarot_card_added.connect(_on_tarot_card_added)
			_player.tarot_card_removed.connect(_on_tarot_card_removed)
			refresh_slots()
			return


func _on_tarot_card_added(_card: TarotCard, _slot: int) -> void:
	refresh_slots()

func _on_tarot_card_removed(_slot: int)->void:
	refresh_slots()

# Redraws every slot from the player's inventory.
func refresh_slots() -> void:
	if not is_instance_valid(_player):
		return

	for i in range(slot_panels.size()):
		var card: TarotCard = null
		if i < _player.tarot_cards.size():
			card = _player.tarot_cards[i]

		var button_hint: String = "[LB]" if i == 0 else "[RB]"
		if card == null:
			_slot_art[i].texture = null
			slot_labels[i].text = button_hint
			slot_panels[i].modulate = Color(1, 1, 1, 0.4)
		else:
			_slot_art[i].texture = card.art
			_slot_art[i].modulate = Color(1, 1, 1, 1)
			slot_labels[i].text = "%s\n%s" % [button_hint, card.card_name]
			slot_panels[i].modulate = Color(1, 1, 1, 1)
