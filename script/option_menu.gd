extends Control

@onready var name_edit = $VBoxContainer/NameEdit
@onready var character_dropdown = $VBoxContainer/CharacterDropdown
@onready var pet_dropdown = $VBoxContainer/PetDropdown
@onready var back_button = $VBoxContainer/BackButton

# Placeholder for saving options
var player_name := Global.player_name
var selected_character := Global.selected_character
var selected_pet := Global.selected_pet

func _ready():
	# Fill character and pet dropdowns
	character_dropdown.clear()
	character_dropdown.add_item("Fighter")
	character_dropdown.add_item("Samurai")
	character_dropdown.add_item("Shinobi")
	
	pet_dropdown.clear()
	pet_dropdown.add_item("Mew")
	pet_dropdown.add_item("Squirtle")
	pet_dropdown.add_item("Yeti")
	
	# Set default or loaded values
	name_edit.text = Global.player_name
	
	# Set the correct character selection
	var char_items = ["Fighter", "Samurai", "Shinobi"]
	var char_index = char_items.find(Global.selected_character)
	if char_index != -1:
		character_dropdown.select(char_index)
	else:
		character_dropdown.select(0)  # Default to first item
	
	# Set the correct pet selection
	var pet_items = ["Mew", "Squirtle", "Yeti"]
	var pet_index = pet_items.find(Global.selected_pet)
	if pet_index != -1:
		pet_dropdown.select(pet_index)
	else:
		pet_dropdown.select(0)  # Default to first item
	
	# Connect back button
	back_button.pressed.connect(_on_back_pressed)

func _on_back_pressed():
	# Save the current selections to Global
	Global.player_name = name_edit.text
	Global.selected_character = character_dropdown.get_item_text(character_dropdown.get_selected_id())
	Global.selected_pet = pet_dropdown.get_item_text(pet_dropdown.get_selected_id())
	
	print("Saved settings - Name:", Global.player_name, " Character:", Global.selected_character, " Pet:", Global.selected_pet)
	
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
