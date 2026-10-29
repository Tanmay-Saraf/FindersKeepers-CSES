extends CanvasLayer

@onready var panel: PanelContainer = $PanelContainer
@onready var name_label: Label = $PanelContainer/VBoxContainer/NameLabel
@onready var description_label: Label = $PanelContainer/VBoxContainer/DescriptionLabel

func _ready() -> void:
	hide_tooltip()

func show_tooltip(card_name: String, card_description: String) -> void:
	name_label.text = card_name
	description_label.text = card_description
	panel.show()

func hide_tooltip() -> void:
	panel.hide()
