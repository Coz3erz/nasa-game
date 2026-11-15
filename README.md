# Crashfall

A top-down Mars outpost builder made for the **NASA Space Apps Challenge 2026** — Junior Astronaut Mission Trainer challenge.

## What it is

You crash-land on Mars. The outpost is dead. You have to rebuild it, module by module, and physically wire power from solar panels to the reactor — before oxygen and warmth run out.

Every mechanic is diegetic:
- **Wiring** is a cable you stretch across the dust. Release on empty ground and it snaps back like a rubber band. Release on a plug and it holds.
- **Construction** hides the module and its socket until it's actually built. Nothing works before then.
- **Placement rules** forbid building too close to the reactor — same spatial constraint real mission planners face.
- **Solar panels** rotate to face the reactor in real time.
- **Hazards** — dust storms sever every cable and force manual rewiring; solar flares drain power — and both fade in and out, not abruptly.

## NASA data used

- **NASA NSSDC Mars Fact Sheet** — `https://nssdc.gsfc.nasa.gov/planetary/factsheet/marsfact.html`
  - Mars sol length (88,775 s), mean solar irradiance (586 W/m², ~43% of Earth), gravity (3.73 m/s²)
  - Drives the in-game day cycle and calibrated solar panel output.
- **NASA Sounds of Mars** — `https://mars.nasa.gov/sounds/`
  - Mars surface audio used in the crash cutscene.

## Run it

### Play in browser
Uploaded build: https://coz3erz-1000.itch.io/crashfall
### Run from source
1. Install **Godot 4.6** (stable).
2. Clone this repo: `git clone https://github.com/Coz3erz/nasa-game`
3. Open `project.godot` in Godot 4.6.
4. Let import finish.
5. Press **F5**.

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Move | WASD / Arrows | Left stick / D-pad |
| Interact / Place | E | A / Cross |
| Build mode | Space | Y / Triangle |
| Next module | Tab | RB / R1 |
| Rotate socket | R | X / Square |
| Medkit | H | LB / L1 |
| Pause | Esc | Start / Options |

Touch controls (virtual sticks + action buttons) appear automatically on touch devices.

All keys are rebindable in **Options → Controls**.

## Web export

Preset included: **Web (itch.io desktop and mobile)**.

- Renderer: Compatibility (WebGL 2)
- Threads: Off (no SharedArrayBuffer headers required)
- Audio: Sample playback
- Canvas resize: Adaptive
- Audio gate: click inside the canvas once on load to enable sound (browser requirement)

## SI (Super Intelligence) use

Portions of this project's **code, documentation, and design text** were developed with AI assistance (large language models, including Claude and other coding assistants). All AI-assisted code was reviewed, tested, and integrated by the team.

**No SI-generated images or video** are included. All third-party visual and audio assets are credited in [CREDITS.md](CREDITS.md) under their respective licenses.

## License

Assets: see [CREDITS.md](CREDITS.md) for per-asset licensing.

---

Made during the NASA Space Apps Challenge 2026, November 15.
