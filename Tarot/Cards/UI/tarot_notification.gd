
extends CanvasLayer

@onready var message_label: Label = $PanelContainer/MessageLabel

var notification_timer: Timer

func _ready() -> void:
	hide()

	notification_timer = Timer.new()
	notification_timer.one_shot = true
	notification_timer.wait_time = 3.0
	add_child(notification_timer)
	notification_timer.timeout.connect(hide)

func show_notification(message: String) -> void:
	message_label.text = message
	notification_timer.start()
	show()
