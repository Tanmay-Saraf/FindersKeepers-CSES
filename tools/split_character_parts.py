"""Bake character FBXs into four static collectible GLBs each.

Run with Blender in background mode from the project root. Each output GLB
contains one mesh named after its body region and keeps the source materials.
"""

import bpy
import bmesh
import glob
import os
from mathutils import Matrix, Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SOURCE_ROOT = os.path.join(ROOT, "Models", "characters")
OUTPUT_ROOT = os.path.join(SOURCE_ROOT, "SplitParts")

# Bone name fragments are matched without the Mixamo namespace prefix.
REGION_BONES = {
    "head": ("head", "neck"),
    "hands": ("shoulder", "arm", "forearm", "hand"),
    "torso": ("hips", "spine"),
    "legs": ("upleg", "leg", "foot", "toe"),
}


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def pose_doll_limbs(armature):
    """Keep both arms straight and bring them side by side without crossing."""
    bones = {bone.name.lower().split(":")[-1]: bone for bone in armature.pose.bones}
    # Pull each shoulder joint inward first. Then set the upper arms to a
    # shallower inward angle to preserve thumb clearance after moving the
    # shoulder roots closer together. Rig posing keeps sleeves and skin aligned.
    armature.data.pose_position = "POSE"
    has_shoulders = "leftshoulder" in bones and "rightshoulder" in bones
    if has_shoulders:
        pose_angles = (
            ("leftshoulder", -1.0472),
            ("rightshoulder", 1.0472),
            ("leftarm", -0.5585),
            ("rightarm", 0.5585),
        )
    else:
        pose_angles = (("leftarm", -1.7802), ("rightarm", 1.7802))
    for name, angle in pose_angles:
        bone = bones.get(name)
        if bone is None:
            continue
        # Rotate around the bone head so child arm/forearm bones inherit the
        # shoulder adjustment while the arms remain straight.
        bpy.context.view_layer.update()
        head = bone.head.copy()
        rotation = Matrix.Rotation(angle, 4, "Z")
        pivot = Matrix.Translation(head)
        bone.matrix = pivot @ rotation @ pivot.inverted() @ bone.matrix
    bpy.context.view_layer.update()


def region_for_polygon(obj, polygon):
    totals = {name: 0.0 for name in REGION_BONES}
    group_names = {group.index: group.name.lower().split(":")[-1] for group in obj.vertex_groups}
    for vertex_index in polygon.vertices:
        vertex = obj.data.vertices[vertex_index]
        for assignment in vertex.groups:
            bone_name = group_names.get(assignment.group, "")
            for region, fragments in REGION_BONES.items():
                if any(fragment in bone_name for fragment in fragments):
                    totals[region] += assignment.weight
    return max(totals, key=totals.get) if max(totals.values()) > 0 else None


def severed_cover_material():
    material = bpy.data.materials.get("CollectibleCutCover_Red")
    if material is None:
        material = bpy.data.materials.new("CollectibleCutCover_Red")
    material.diffuse_color = (0.34, 0.008, 0.018, 1.0)
    material.use_nodes = True
    material.use_backface_culling = False
    shader = material.node_tree.nodes.get("Principled BSDF")
    if shader:
        shader.inputs["Base Color"].default_value = (0.34, 0.008, 0.018, 1.0)
        shader.inputs["Roughness"].default_value = 0.82
    return material


def neck_opening_edges(source, bm, open_edges, head_faces, head_height):
    """Choose the centered, horizontal source opening at the base of the neck."""
    if not any(tag in source.name.lower() for tag in ("body", "skin")):
        return []
    if not open_edges or not head_faces:
        return []

    head_verts = {vertex for face in head_faces for vertex in face.verts}
    world_coords = {vertex: source.matrix_world @ vertex.co for vertex in head_verts}
    center_x = (min(value.x for value in world_coords.values()) + max(value.x for value in world_coords.values())) * 0.5
    center_y = (min(value.y for value in world_coords.values()) + max(value.y for value in world_coords.values())) * 0.5
    horizontal_size = max(
        max(value.x for value in world_coords.values()) - min(value.x for value in world_coords.values()),
        max(value.y for value in world_coords.values()) - min(value.y for value in world_coords.values()),
        1e-6,
    )
    bottom_z = min(value.z for value in world_coords.values())
    center_tolerance = horizontal_size * 0.28
    height_tolerance = max(head_height * 0.12, 1e-4)
    perimeter_tolerance = head_height * 0.35

    remaining = set(open_edges)
    candidates = []
    while remaining:
        component = set()
        pending = [remaining.pop()]
        while pending:
            edge = pending.pop()
            component.add(edge)
            for vertex in edge.verts:
                for adjacent in vertex.link_edges:
                    if adjacent in remaining:
                        remaining.remove(adjacent)
                        pending.append(adjacent)
        vertices = {vertex for edge in component for vertex in edge.verts}
        coords = [source.matrix_world @ vertex.co for vertex in vertices]
        center = sum(coords, Vector((0.0, 0.0, 0.0))) / len(coords)
        perimeter = sum(
            (source.matrix_world.to_3x3() @ (edge.verts[1].co - edge.verts[0].co)).length
            for edge in component
        )
        z_span = max(value.z for value in coords) - min(value.z for value in coords)
        centered = ((center.x - center_x) ** 2 + (center.y - center_y) ** 2) ** 0.5
        near_neck_base = center.z <= bottom_z + height_tolerance
        roughly_horizontal = z_span <= max(head_height * 0.18, 1e-4)
        if (perimeter >= perimeter_tolerance and centered <= center_tolerance
                and near_neck_base and roughly_horizontal):
            candidates.append((center.z, -perimeter, component))

    if not candidates:
        return []
    return list(min(candidates, key=lambda candidate: (candidate[0], candidate[1]))[2])


def make_static_region(source, evaluated_mesh, region, face_regions):
    duplicate = source.copy()
    duplicate.data = evaluated_mesh.copy()
    duplicate.name = region
    bpy.context.collection.objects.link(duplicate)
    duplicate.parent = None
    duplicate.matrix_world = source.matrix_world.copy()
    duplicate.modifiers.clear()
    duplicate.data.materials.append(severed_cover_material())
    cover_material_index = len(duplicate.data.materials) - 1
    # Remove faces assigned to other regions. Loose vertices are removed too.
    mesh = duplicate.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    face_regions_by_face = dict(zip(bm.faces, face_regions))
    head_faces = [face for face, assigned in face_regions_by_face.items() if assigned == region]
    region_coords = [source.matrix_world @ vertex.co for face in head_faces for vertex in face.verts]
    head_height = (max(point.z for point in region_coords) - min(point.z for point in region_coords)) if region_coords else 0.0
    split_edges = [
        edge for edge in bm.edges
        if region in {face_regions_by_face.get(face) for face in edge.link_faces}
        and any(face_regions_by_face.get(face) != region for face in edge.link_faces)
    ]
    source_open_edges = [
        edge for edge in bm.edges
        if len(edge.link_faces) == 1 and face_regions_by_face.get(edge.link_faces[0]) == region
    ]
    discard = [face for face, assigned in zip(bm.faces, face_regions) if assigned != region]
    bmesh.ops.delete(bm, geom=discard, context="FACES")
    cut_edges = [
        edge for edge in split_edges if edge.is_valid and len(edge.link_faces) == 1
    ]
    if region == "head":
        cut_edges.extend(neck_opening_edges(source, bm, source_open_edges, head_faces, head_height))
    cut_edges = list(set(cut_edges))
    if cut_edges:
        filled = bmesh.ops.holes_fill(bm, edges=cut_edges, sides=0)
        for face in filled.get("faces", []):
            face.material_index = cover_material_index
        if filled.get("faces"):
            bmesh.ops.recalc_face_normals(bm, faces=filled["faces"])
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    if not mesh.polygons:
        bpy.data.objects.remove(duplicate, do_unlink=True)
        return None

    # The mesh data was copied from Blender's evaluated armature result, so it
    # is already deformed into the doll pose and needs no rig at runtime.
    duplicate.vertex_groups.clear()
    return duplicate


def process(source_path):
    clear_scene()
    bpy.ops.import_scene.fbx(filepath=source_path)
    bpy.ops.object.select_all(action="DESELECT")
    armature = next((obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"), None)
    if armature is None:
        raise RuntimeError("No armature found in " + source_path)
    pose_doll_limbs(armature)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("No meshes found in " + source_path)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated_meshes = {}
    for source in meshes:
        evaluated = source.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        evaluated_meshes[source] = mesh.copy()
        evaluated.to_mesh_clear()
    face_regions = {
        source: [region_for_polygon(source, polygon) for polygon in source.data.polygons]
        for source in meshes
    }
    model_name = os.path.basename(source_path).rsplit(".", 1)[0]
    relative_source_dir = os.path.relpath(os.path.dirname(source_path), SOURCE_ROOT)
    out_dir = os.path.join(OUTPUT_ROOT, relative_source_dir)
    os.makedirs(out_dir, exist_ok=True)

    for region in REGION_BONES:
        outputs = []
        for source in meshes:
            part = make_static_region(
                source,
                evaluated_meshes[source],
                region,
                face_regions[source],
            )
            if part:
                outputs.append(part)
        if not outputs:
            raise RuntimeError(f"{model_name} produced no {region} geometry")

        # Export the region's meshes together. Keeping multiple source meshes
        # avoids changing their material boundaries while remaining one GLB.
        bpy.ops.object.select_all(action="DESELECT")
        for obj in outputs:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = outputs[0]
        bpy.ops.export_scene.gltf(
            filepath=os.path.join(out_dir, f"{region}.glb"),
            export_format="GLB",
            export_image_format="JPEG",
            export_image_quality=75,
            use_selection=True,
            export_apply=True,
        )
        for obj in outputs:
            bpy.data.objects.remove(obj, do_unlink=True)

    print(f"SPLIT_OK {model_name} -> {out_dir}")


if __name__ == "__main__":
    character_filter = os.environ.get("CHARACTER_FILTER", "")
    source_paths = set(glob.glob(os.path.join(SOURCE_ROOT, "**", "*.fbx"), recursive=True))
    source_paths.update(glob.glob(os.path.join(SOURCE_ROOT, "**", "*.FBX"), recursive=True))
    output_prefix = os.path.abspath(OUTPUT_ROOT) + os.sep
    source_paths = sorted(
        path for path in source_paths
        if not os.path.abspath(path).startswith(output_prefix)
        and (not character_filter or character_filter in path)
    )
    if not source_paths:
        raise RuntimeError(f"No character FBX files found under {SOURCE_ROOT}")

    failures = []
    for path in source_paths:
        try:
            process(path)
        except Exception as error:
            failures.append((path, error))
            print(f"SPLIT_FAILED {path}: {error}")
    print(f"SPLIT_SUMMARY {len(source_paths) - len(failures)} succeeded, {len(failures)} failed")
    if failures:
        raise RuntimeError(f"Failed to split {len(failures)} character model(s)")
