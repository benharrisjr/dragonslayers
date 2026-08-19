#!/usr/bin/env python3
"""Convert art/models/dragon.3ds into a rigged art/models/dragon.glb.

Godot imports glTF, OBJ, FBX, DAE and .blend -- not .3ds -- so the source model needs a
conversion pass before the engine can see it at all. Blender is not installed on this
machine, and the 3DS format is simple enough that shelling out to a DCC tool would be more
fragile than reading the chunks directly, so this is dependency-free: no numpy, no trimesh.

Three things happen beyond a format swap:

  * Reorientation. 3DS is Z-up with Y running nose-to-tail; Godot is Y-up with -Z forward.
    The mapping (x, y, z) -> (-x, z, y) is a proper rotation (determinant +1), so face
    winding survives untouched -- the mirror on X is free on a bilaterally symmetric model.

  * Flat shading. The source has no UVs and no smoothing groups, so vertices are split per
    face and given the face normal, and the two 3DS material colours are baked into COLOR_0.
    One vertex-coloured material then draws the whole dragon in a single surface, which is
    also what makes it match the faceted KayKit/Kenney art.

  * Skinning. The mesh arrives as one rigid lump named "Body", but the fight needs a wing
    flap, a tail sweep, a claw swipe and a breath wind-up. BONES below defines a 20-bone rig
    by hand, measured off the real geometry, and each vertex is weighted to the two nearest
    bone segments. Segments rather than points because the wings and tail are long: a point
    distance would make the wing tip bind to the shoulder.

Animations are deliberately NOT emitted here -- they are authored on this rig in
scenes/enemies/dragon.tscn, so timings can be tuned against live hitboxes in the editor
instead of by re-running a script.

    python3 tools/convert_dragon.py
"""

import json
import math
import os
import struct
import sys

SRC = "art/models/dragon.3ds"
DST = "art/models/dragon.glb"

## Source units are ~281 tall; 0.02 puts the dragon at 5.6 m with a 12.6 m wingspan, about
## three times a KayKit adventurer -- big enough to read as a boss, small enough for an arena.
SCALE = 0.02

## Weight falloff exponent. Higher binds more locally, which keeps the legs and head crisp;
## lower smears the wing roots. 4 was picked by looking at the debug weight render.
FALLOFF = 4.0

# --- the rig ---------------------------------------------------------------------------
#
# Positions are in final Godot space: metres, feet on Y=0, head towards -Z, origin under the
# chest. "seg" is the capsule-ish line segment a vertex measures its distance to, which is
# not always the bone's own length -- the head's segment covers the skull, not the neck.
#
#   name              parent        joint position          influence segment
BONES = [
    ("root",          None,   (0.00, 0.00,  0.00), None),
    ("hips",          "root", (0.00, 3.05,  0.55), ((0.00, 3.05,  0.90), (0.00, 3.15,  0.00))),
    ("spine",         "hips", (0.00, 3.15, -0.45), ((0.00, 3.15,  0.10), (0.00, 3.40, -0.90))),
    ("chest",         "spine",(0.00, 3.55, -1.45), ((0.00, 3.40, -0.90), (0.00, 3.90, -1.90))),
    ("neck",          "chest",(0.00, 4.35, -2.25), ((0.00, 3.90, -1.90), (0.00, 4.35, -2.60))),
    ("head",          "neck", (0.00, 4.35, -2.95), ((0.00, 4.30, -2.60), (0.00, 4.30, -3.20))),
    ("tail_1",        "hips", (0.00, 2.55,  1.55), ((0.00, 2.90,  1.00), (0.00, 2.40,  2.00))),
    ("tail_2",        "tail_1",(0.00, 2.15, 2.55), ((0.00, 2.40,  2.00), (0.00, 2.05,  3.10))),
    ("tail_3",        "tail_2",(0.00, 1.95, 3.75), ((0.00, 2.05,  3.10), (0.00, 1.90,  4.30))),
    ("tail_4",        "tail_3",(0.00, 1.85, 4.95), ((0.00, 1.90,  4.30), (0.00, 1.85,  5.80))),
    ("wing_l_root",   "chest",(0.90, 4.40, -1.20), ((0.70, 4.30, -1.40), (2.60, 4.60, -0.20))),
    ("wing_l_mid",    "wing_l_root",(3.30, 4.60, 0.20), ((2.60, 4.60, -0.20), (4.60, 4.40, 0.80))),
    ("wing_l_tip",    "wing_l_mid",(6.00, 4.00, 1.30), ((4.60, 4.40, 0.80), (6.40, 3.60, 1.60))),
    ("wing_r_root",   "chest",(-0.90, 4.40, -1.20), ((-0.70, 4.30, -1.40), (-2.60, 4.60, -0.20))),
    ("wing_r_mid",    "wing_r_root",(-3.30, 4.60, 0.20), ((-2.60, 4.60, -0.20), (-4.60, 4.40, 0.80))),
    ("wing_r_tip",    "wing_r_mid",(-6.00, 4.00, 1.30), ((-4.60, 4.40, 0.80), (-6.40, 3.60, 1.60))),
    ("leg_fl",        "chest",(0.60, 2.20, -1.75), ((0.60, 2.20, -1.75), (0.60, 0.00, -1.80))),
    ("leg_fr",        "chest",(-0.60, 2.20, -1.75), ((-0.60, 2.20, -1.75), (-0.60, 0.00, -1.80))),
    ("leg_bl",        "hips", (0.60, 2.20,  0.35), ((0.60, 2.20,  0.35), (0.60, 0.00,  0.30))),
    ("leg_br",        "hips", (-0.60, 2.20, 0.35), ((-0.60, 2.20, 0.35), (-0.60, 0.00, 0.30))),
]

## root exists as a floor-level pivot for whole-body motion (the lunge, the death topple) and
## must never pull vertices with it, so it is excluded from weighting.
UNWEIGHTED = {"root"}


# --- 3DS reading -----------------------------------------------------------------------

CHUNK_MAIN, CHUNK_EDIT, CHUNK_OBJECT = 0x4D4D, 0x3D3D, 0x4000
CHUNK_TRIMESH, CHUNK_VERTS, CHUNK_FACES = 0x4100, 0x4110, 0x4120
CHUNK_FACEMAT, CHUNK_MATERIAL = 0x4130, 0xAFFF
CHUNK_MATNAME, CHUNK_DIFFUSE = 0xA000, 0xA020
CHUNK_COLOR24, CHUNK_COLORF = 0x0011, 0x0010


def read_3ds(path):
    data = open(path, "rb").read()

    def cstr(off):
        end = data.index(b"\0", off)
        return data[off:end].decode("latin1"), end + 1

    verts, faces, facemats, materials = [], [], {}, {}
    current_material = [None]

    def walk(off, end):
        while off < end - 5:
            cid, clen = struct.unpack("<HI", data[off:off + 6])
            if clen < 6 or off + clen > end:
                return
            body = off + 6
            if cid == CHUNK_VERTS:
                n = struct.unpack("<H", data[body:body + 2])[0]
                raw = struct.unpack("<%df" % (n * 3), data[body + 2:body + 2 + n * 12])
                verts.extend((raw[i * 3], raw[i * 3 + 1], raw[i * 3 + 2]) for i in range(n))
            elif cid == CHUNK_FACES:
                n = struct.unpack("<H", data[body:body + 2])[0]
                raw = struct.unpack("<%dH" % (n * 4), data[body + 2:body + 2 + n * 8])
                faces.extend((raw[i * 4], raw[i * 4 + 1], raw[i * 4 + 2]) for i in range(n))
                walk(body + 2 + n * 8, off + clen)  # FACEMAT lives after the face array
            elif cid == CHUNK_FACEMAT:
                name, p = cstr(body)
                n = struct.unpack("<H", data[p:p + 2])[0]
                idx = struct.unpack("<%dH" % n, data[p + 2:p + 2 + n * 2])
                facemats[name] = idx
            elif cid == CHUNK_MATERIAL:
                current_material[0] = None
                walk(body, off + clen)
            elif cid == CHUNK_MATNAME:
                current_material[0] = cstr(body)[0]
                materials.setdefault(current_material[0], (1.0, 1.0, 1.0))
            elif cid == CHUNK_DIFFUSE:
                sub, sublen = struct.unpack("<HI", data[body:body + 6])
                if sub == CHUNK_COLOR24:
                    r, g, b = data[body + 6:body + 9]
                    col = (r / 255.0, g / 255.0, b / 255.0)
                elif sub == CHUNK_COLORF:
                    col = struct.unpack("<3f", data[body + 6:body + 18])
                else:
                    col = (1.0, 1.0, 1.0)
                if current_material[0]:
                    materials[current_material[0]] = col
            elif cid in (CHUNK_MAIN, CHUNK_EDIT, CHUNK_OBJECT, CHUNK_TRIMESH):
                walk(cstr(body)[1] if cid == CHUNK_OBJECT else body, off + clen)
            off += clen

    walk(0, len(data))
    return verts, faces, facemats, materials


# --- geometry helpers --------------------------------------------------------------------

def to_godot(v):
    """3DS Z-up (X wingspan, Y nose-to-tail, Z height) -> Godot Y-up, -Z forward."""
    x, y, z = v
    return (-x * SCALE, z * SCALE, y * SCALE)


def srgb_to_linear(c):
    ## glTF COLOR_0 is linear; the 3DS colours are sRGB swatches from a modelling app.
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def dist_to_segment(p, a, b):
    ab = tuple(b[i] - a[i] for i in range(3))
    ap = tuple(p[i] - a[i] for i in range(3))
    denom = sum(c * c for c in ab)
    t = 0.0 if denom == 0.0 else max(0.0, min(1.0, sum(ap[i] * ab[i] for i in range(3)) / denom))
    closest = tuple(a[i] + ab[i] * t for i in range(3))
    return math.sqrt(sum((p[i] - closest[i]) ** 2 for i in range(3)))


def skin_weights(pos, weightable):
    """Bind a vertex to its two nearest bone segments, inverse-distance weighted."""
    scored = sorted(
        ((dist_to_segment(pos, seg[0], seg[1]), bone_index) for bone_index, seg in weightable),
        key=lambda pair: pair[0],
    )[:2]
    raw = [(1.0 / max(d, 1e-4)) ** FALLOFF for d, _ in scored]
    total = sum(raw) or 1.0
    joints = [idx for _, idx in scored] + [0, 0]
    weights = [w / total for w in raw] + [0.0, 0.0]
    return joints[:4], weights[:4]


# --- glTF writing ------------------------------------------------------------------------

class GLB:
    """Minimal glTF 2.0 binary writer: enough accessors for a flat-shaded skinned mesh."""

    def __init__(self):
        self.buffer = bytearray()
        self.views = []
        self.accessors = []

    def _view(self, blob, target=None):
        while len(self.buffer) % 4:
            self.buffer.append(0)
        offset = len(self.buffer)
        self.buffer.extend(blob)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(blob)}
        if target:
            view["bufferViewTarget"] = target
        self.views.append(view)
        return len(self.views) - 1

    def accessor(self, values, comp_type, kind, fmt, target=None, minmax=False):
        flat = []
        for v in values:
            flat.extend(v if isinstance(v, (list, tuple)) else [v])
        blob = struct.pack("<%d%s" % (len(flat), fmt), *flat)
        acc = {
            "bufferView": self._view(blob, target),
            "componentType": comp_type,
            "count": len(values),
            "type": kind,
        }
        if minmax:
            cols = list(zip(*values))
            acc["min"] = [min(c) for c in cols]
            acc["max"] = [max(c) for c in cols]
        self.accessors.append(acc)
        return len(self.accessors) - 1

    def write(self, path, gltf):
        gltf["bufferViews"] = self.views
        gltf["accessors"] = self.accessors
        gltf["buffers"] = [{"byteLength": len(self.buffer)}]
        js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
        js += b" " * ((4 - len(js) % 4) % 4)
        bin_blob = bytes(self.buffer) + b"\0" * ((4 - len(self.buffer) % 4) % 4)
        total = 12 + 8 + len(js) + 8 + len(bin_blob)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<II", len(js), 0x4E4F534A))
            f.write(js)
            f.write(struct.pack("<II", len(bin_blob), 0x004E4942))
            f.write(bin_blob)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src, dst = os.path.join(root, SRC), os.path.join(root, DST)
    if not os.path.exists(src):
        sys.exit("missing %s" % src)

    verts, faces, facemats, materials = read_3ds(src)
    print("read %d verts, %d faces, %d materials" % (len(verts), len(faces), len(materials)))

    positions = [to_godot(v) for v in verts]
    ## Feet on the floor and the body centred over the origin, so the scene can be dropped
    ## straight onto terrain without a fudge offset in the .tscn.
    min_y = min(p[1] for p in positions)
    cx = (min(p[0] for p in positions) + max(p[0] for p in positions)) * 0.5
    positions = [(p[0] - cx, p[1] - min_y, p[2]) for p in positions]

    face_colour = {}
    for mat_name, indices in facemats.items():
        r, g, b = materials.get(mat_name, (1.0, 1.0, 1.0))
        colour = (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), 1.0)
        for fi in indices:
            face_colour[fi] = colour
    default_colour = (srgb_to_linear(0.5), srgb_to_linear(0.5), srgb_to_linear(0.5), 1.0)

    index_of = {name: i for i, (name, _, _, _) in enumerate(BONES)}
    weightable = [(i, seg) for i, (name, _, _, seg) in enumerate(BONES)
                  if seg and name not in UNWEIGHTED]
    vert_skin = [skin_weights(p, weightable) for p in positions]

    out_pos, out_nrm, out_col, out_joints, out_weights = [], [], [], [], []
    for fi, face in enumerate(faces):
        a, b, c = (positions[i] for i in face)
        u = tuple(b[i] - a[i] for i in range(3))
        w = tuple(c[i] - a[i] for i in range(3))
        n = (u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0])
        length = math.sqrt(sum(t * t for t in n)) or 1.0
        n = tuple(t / length for t in n)
        colour = face_colour.get(fi, default_colour)
        for vi in face:
            out_pos.append(positions[vi])
            out_nrm.append(n)
            out_col.append(colour)
            joints, weights = vert_skin[vi]
            out_joints.append(joints)
            out_weights.append(weights)

    glb = GLB()
    acc_pos = glb.accessor(out_pos, 5126, "VEC3", "f", 34962, minmax=True)
    acc_nrm = glb.accessor(out_nrm, 5126, "VEC3", "f", 34962)
    acc_col = glb.accessor(out_col, 5126, "VEC4", "f", 34962)
    acc_joint = glb.accessor(out_joints, 5123, "VEC4", "H", 34962)
    acc_weight = glb.accessor(out_weights, 5126, "VEC4", "f", 34962)
    acc_idx = glb.accessor(list(range(len(out_pos))), 5125, "SCALAR", "I", 34963)

    ## Bones carry no rotation in rest pose, so the inverse bind matrix is a plain negative
    ## translation -- worth stating because it is why no matrix maths appears here.
    ibms = []
    for _, _, pos, _ in BONES:
        m = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, -pos[0], -pos[1], -pos[2], 1.0]
        ibms.append(m)
    acc_ibm = glb.accessor(ibms, 5126, "MAT4", "f")

    nodes = [{"name": "Dragon", "mesh": 0, "skin": 0}]
    bone_node_base = len(nodes)
    for name, parent, pos, _ in BONES:
        local = pos if parent is None else tuple(
            pos[i] - BONES[index_of[parent]][2][i] for i in range(3))
        nodes.append({"name": name, "translation": list(local)})
    for i, (name, parent, _, _) in enumerate(BONES):
        if parent is None:
            continue
        p = nodes[bone_node_base + index_of[parent]]
        p.setdefault("children", []).append(bone_node_base + i)

    gltf = {
        "asset": {"version": "2.0", "generator": "dragonslayers tools/convert_dragon.py"},
        "scene": 0,
        "scenes": [{"nodes": [0, bone_node_base]}],
        "nodes": nodes,
        "skins": [{
            "name": "DragonRig",
            "inverseBindMatrices": acc_ibm,
            "skeleton": bone_node_base,
            "joints": [bone_node_base + i for i in range(len(BONES))],
        }],
        "materials": [{
            "name": "dragon_scales",
            "pbrMetallicRoughness": {
                "baseColorFactor": [1, 1, 1, 1],
                "metallicFactor": 0.0,
                "roughnessFactor": 0.85,
            },
        }],
        "meshes": [{
            "name": "Body",
            "primitives": [{
                "attributes": {
                    "POSITION": acc_pos, "NORMAL": acc_nrm, "COLOR_0": acc_col,
                    "JOINTS_0": acc_joint, "WEIGHTS_0": acc_weight,
                },
                "indices": acc_idx,
                "material": 0,
            }],
        }],
    }
    glb.write(dst, gltf)

    size = os.path.getsize(dst)
    height = max(p[1] for p in positions)
    span = max(p[0] for p in positions) - min(p[0] for p in positions)
    length = max(p[2] for p in positions) - min(p[2] for p in positions)
    print("wrote %s (%.1f KB): %d verts, %d bones" % (DST, size / 1024, len(out_pos), len(BONES)))
    print("  %.2f m tall, %.2f m wingspan, %.2f m nose-to-tail" % (height, span, length))


if __name__ == "__main__":
    main()
