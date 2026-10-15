# Adding a playable character

1. Add the imported character scene under `Models/characters/`.
2. Create a `CharacterDefinition` resource in `Models/characters/Definitions/`.
   Set its unique `character_id`, display name, model scene, vertical offset,
   and scale. Tune offset and scale per model so it fits the player capsule.
3. Add the definition to `CharacterCatalog.tres`.

The player uses `default_character_id` on its `AnimationController` to choose
the startup character. A future selector can list
`AnimationController.character_catalog.characters` and switch models with
`set_character_definition(definition)` or `set_character_by_id(character_id)`.

Models need a `Skeleton3D` with Mixamo-compatible bone names for the existing
animation retargeting to work.
