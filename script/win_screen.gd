extends Control

@onready var win_button: Button = $WinButton

func _on_return_button_pressed():
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _ready():
	$WinButton.pressed.connect(_on_return_button_pressed)
