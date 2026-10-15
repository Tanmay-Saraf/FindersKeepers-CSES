# Collectible character parts

Each character directory contains `head.glb`, `torso.glb`, `hands.glb`, and
`legs.glb` generated from that character's FBX. The meshes keep their original
materials and are baked into a static doll pose. Legs retain their original
pose. These are visual assets; the existing `BodyPart.tscn` pickup still needs
to be wired to the matching GLB when the game spawns a collectible.
Newly exposed cut edges are capped with a dark red material for the horror look.

The split assigns each face to the body region with the strongest combined
skinning weight from the source skeleton. The cuts follow bone influence, so
they are functional region splits rather than artist-authored, capped seams.
Hands includes both arms and hands.

To regenerate the assets, run this from the project root or pass its full path:

```sh
./tools/generate_body_parts.sh
```

The launcher finds `.fbx` and `.FBX` files recursively under
`Models/characters/`, skips the generated `SplitParts` directory, and writes
four GLBs beside each character's corresponding subfolder under `SplitParts/`.
Blender must be installed. If it is not on `PATH`, set `BLENDER_BIN` to its
executable path (for example, `BLENDER_BIN=/path/to/blender`). To process only
one matching character, use `CHARACTER_FILTER=Player3` before the command.
