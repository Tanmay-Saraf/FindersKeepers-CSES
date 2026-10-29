# Terrain texture pack

These are copies of the source images currently in `Textures/terrain/`. They
are kept together here so the terrain materials can be recreated in another
project. The files are 1K (1024 × 1024) JPEG maps.

## Maps

| Set | Albedo / diffuse | Normal (OpenGL) | Other map |
| --- | --- | --- | --- |
| Green Grass | `green_grass_diff_1k.jpg` | `green_grass_nor_gl_1k.jpg` | — |
| Grass Ground | `grass_ground_diff_1k.jpg` | `grass_ground_nor_gl_1k.jpg` | `grass_ground_rough_1k.jpg` |
| Rock Ground | `rock_ground_diff_1k.jpg` | `rock_ground_nor_gl_1k.jpg` | — |
| Sand 03 | `sand_03_diff_1k.jpg` | `sand_03_nor_gl_1k.jpg` | — |

In Godot/Terrain3D, use each `*_diff_*` file as the albedo texture and its
matching `*_nor_gl_*` file as the normal texture. The grass roughness map is
included as part of the downloaded set; the current Terrain3D asset resource
does not assign it.

## Source and license notes

The `rock_ground`, `grass_ground`, and `sand_03` names match the corresponding
Poly Haven texture sets, which are CC0:

- Rock Ground: https://polyhaven.com/a/rock_ground
- Grass Ground: https://polyhaven.com/a/grass_ground
- Sand 03: https://polyhaven.com/a/sand_03

The project does not preserve the original source page or source filename for
the `green_grass_*` pair, so its exact provenance and license are not asserted
here. The images are copied as-is from the project texture folder.
