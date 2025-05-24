extends Control

@onready var name_edit = $VBoxContainer/NameEdit
@onready var character_dropdown = $VBoxContainer/CharacterDropdown
@onready var pet_dropdown = $VBoxContainer/PetDropdown
@onready var back_button = $VBoxContainer/BackButton

# Placeholder for saving options
var player_name := "New Name"
var selected_character := ""
var selected_pet := ""

func _ready():
	# Fill character and pet dropdowns
	character_dropdown.clear()
	character_dropdown.add_item("Knight")
	character_dropdown.add_item("Ninja")
	character_dropdown.add_item("Samurai")

	pet_dropdown.clear()
	pet_dropdown.add_item("Dragon")
	pet_dropdown.add_item("Wolf")
	pet_dropdown.add_item("Fairy")

	# Set default or loaded values
	name_edit.text = player_name
	character_dropdown.select(0)
	pet_dropdown.select(0)

	# Connect back button
	back_button.pressed.connect(_on_back_pressed)

func _on_back_pressed():
	player_name = name_edit.text
	selected_character = character_dropdown.get_item_text(character_dropdown.get_selected())
	selected_pet = pet_dropdown.get_item_text(pet_dropdown.get_selected())

	print("Saved Settings:")
	print("Name:", player_name)
	print("Character:", selected_character)
	print("Pet:", selected_pet)

	# TODO: Save to global state or singleton, then go back to menu
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
