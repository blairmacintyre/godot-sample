# Office VR asset

A lightweight, photo-guided reconstruction of the office in the eight supplied reference pictures. The room, desk, treadmill, chairs, table, cabinet, bookcase, door, glazing, ceiling, and small accessories are actual 3D geometry.

## Open the model

- **office.glb** — complete, textured glTF 2.0 model, with a closed door and full ceiling.
- **preview.html** — self-contained offline browser preview. Double-click it in a modern browser with WebGL enabled. Use the view buttons to inspect the room and the door button to open it. The Overview view hides the entry wall, right wall, ceiling, and door for inspection only; they remain present in the GLB.
- **office_collision.glb** — separate, low-detail geometry for creating collision shapes. Do not render this file in the game.
- **colliders.json** — exact box/cylinder definitions, parent names, and transforms for the collision shapes.
- **asset_info.json** — dimensions, geometry counts, recommended player spawn, and modeling assumptions.
- **validation.json** — results from the Khronos glTF Validator.
- **source/** — reproducible Python model generator and preview source.
- **preview_*.png** — rendered views of the actual GLB.

## Scale and reference fidelity

| Dimension | Value | Basis |
|---|---:|---|
| Maximum interior width, X | 3.7846 m / 12′5″ | User measurement |
| Interior depth, Z | 3.6576 m / 12′ | Estimated |
| Ceiling height, Y | 2.7432 m / 9′ | Estimated |
| Desktop | 1.82 × 0.762 m | Widened following user correction |
| Treadmill | 0.555 × 1.30 m | Estimated |
| Filing cabinet body | 0.34 wide × 0.62 deep × 0.58 m high | Revised to face desk |

The supplied width is interpreted as the maximum inside distance from the taupe wall to the opposite wall. The rear-wall step, all other dimensions, and furniture positions are approximations. This is a modeled reconstruction, not a photogrammetry scan. Textures are original procedural materials; the source photographs are not embedded or redistributed. Exterior/corridor geometry beyond the sidelight and door was not observable and is not included.

The revised desktop is 4.2 cm from the taupe wall and 64 cm farther into the room than the first draft. Its visitor-facing edge and the treadmill end both lie at Z = 0.081 m. The treadmill and office chair sit beside each other with a 10.25 cm gap between their closest X extents. The visitor chair is centered on the desk and faces it. The filing cabinet faces −X toward the desk; its narrow front reduces interference with the meeting chair. Each square ceiling light has a recessed reflector well and one cylindrical tube across the middle.

Both desktop power-box cords wrap tightly around the desktop edges and connect to an underside-mounted power strip. Cable clips keep the runs against the underside; neither cord hangs down or runs to the floor.

## Game integration

Coordinates are right-handed, Y-up, in metres. The room's floor center is the origin. The entrance is at +Z, the taupe wall at −X. Keep a metre-based import scale or convert once if your engine uses another unit.

Furniture objects have meaningful names and floor-level pivots. Keep the door's pivot: **Door_Hinge** is on the jamb. **Door_Open** and **Door_Close** are one-second rotation clips; open is −95 degrees about local Y in the GLB coordinate system. Imported axis conversion may change the axis/sign in an engine. The preview also demonstrates the hinge movement.

Collision shapes are supplied separately because GLB has no universal built-in collision behavior. For each JSON entry, create the listed shape under its named visual parent, using its local `center` and `yaw_radians`. `size` contains full dimensions; cylinder size is diameter, height, diameter. `parent_position` and `parent_yaw_radians` describe the parent's initial transform. Parent the door collision to the hinge so it rotates with the leaf. If using the proxy GLB instead, convert its individual closed pieces to appropriate box or convex colliders and hide their renderers. Do not merge the entire room into one convex hull.

Suggested player floor position is **(0.15, 0, 0.85)**, facing −Z. This is a starting point for your locomotion setup, not a navigation mesh. Chairs use conservative compound collision shapes; the floor beneath their seats is intentionally blocked for player collision.

The GLB uses standard metallic/roughness materials and four embedded PNG textures. It contains no external file dependencies, baked lighting, cameras, or engine-specific shaders. Lighting in the browser preview is illustrative. Textured surfaces have UV0; a non-overlapping lightmap UV set is not included. Generate lightmap UVs in your engine/DCC if baking lighting. Use your game's lighting and reflection settings, batch static surfaces where appropriate, and set glass transparency/shadow behavior for your renderer.

Geometry is intended for real-time VR use, with low polygon counts and simple collision. Actual headset frame rate has not been measured; it depends on lighting, shadow maps, shader settings, resolution, and the rest of the game. The preview is a desktop inspection tool, not a VR player.

## Rebuild or edit

The generator requires Python 3, NumPy, and Pillow:

```sh
python3 source/build_office.py
python3 source/build_preview.py
```

Run the first command after changing furniture dimensions/positions in `source/build_office.py`. The second refreshes the embedded preview from the new GLB and the bundled Three.js sources. Regenerate the PNG previews using the preview's save button after edits.

Three.js is included under its MIT license; see `viewer/vendor/LICENSE.txt`. The model and its procedural textures are newly authored for this request. The original photos remain in their original folder.
