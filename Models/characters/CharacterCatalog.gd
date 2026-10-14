extends Resource
class_name CharacterCatalog

## Ordered character definitions available to a future character selector.
@export var characters: Array[CharacterDefinition] = []


func get_character(character_id: StringName) -> CharacterDefinition:
	for character in characters:
		if character != null and character.character_id == character_id:
			return character
	return null
