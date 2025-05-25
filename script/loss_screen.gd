extends Control

@onready var lose_button: Button = $LoseButton

func _on_return_button_pressed():
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _ready():
	$LoseButton.pressed.connect(_on_return_button_pressed)
