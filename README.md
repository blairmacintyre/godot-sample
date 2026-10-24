When I got a Steam Frame, I decided to try vibe-coding a VR app to see what it's like working with Claude and Godot. A small office (from `office_vr/`) standing on a grid floor under a fancy animated skybox. Teleport around, push the furniture where you like, swing the door open and flip the light switch.

- **Grab** (trigger or grip) while touching something:
  - **Furniture** (desk, desk chair, treadmill, guest chairs, bookcase, table, filing cabinet, waste bin) slides along the floor with your hand; twist your wrist to turn it. It stops at walls and shoves other furniture aside.
  - **The door** swings on its hinge as you move your hand.
  - **The light switch** by the door turns both ceiling lights on and off.
- **Teleport**: push the thumbstick forward to aim and release to go. The arc only lands on open floor.
- **Snap turn**: flick the thumbstick left or right.  

Works on Steam Frame and Quest3, includes proper controller models.

## Web (WebXR)

`./build-web.sh` exports a browser build to `build/web/`. Browsers only allow WebXR on HTTPS pages or on localhost:

- `./build-web.sh --serve` serves it at http://localhost:8000 for a desktop browser (flat preview, no headset).
- `./build-web.sh --serve --quest` also forwards the port to a USB-connected Quest, so its browser can open http://localhost:8000 and show **Enter VR**.
- To play from any headset, upload `build/web/` to any HTTPS static host. The build is single-threaded, so it needs no special server headers.

The web build uses the Compatibility renderer and WebXR's own controller input. It shows the browser's controller models from the WebXR Input Profiles project (MIT licensed, bundled in `webxr_controllers/` for Quest 3/3S, Quest Pro, Quest 2 and a generic fallback), with buttons, trigger and thumbstick that move.
