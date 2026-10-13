# GTA HTTP GPU server (Roblox stream)

Runs the browser GTA port ([gta.deloskiyt.pl](https://gta.deloskiyt.pl/)) in a hidden, GPU-accelerated
Edge window on your PC and streams it into the Roblox place as a full-screen display. Roblox sends your
keyboard and mouse back to the game. Everything runs locally; Roblox Studio only talks to `http://127.0.0.1:8765`.

## You need

- Windows 10/11 with a real GPU (anything that runs the game in a browser) and ideally 16 GB RAM
  (the game alone takes ~3 GB; 8 GB works if you close Discord and spare browser tabs).
- Microsoft Edge (already on Windows).
- Python 3.9+ from <https://www.python.org/downloads/windows/> — tick **"Add python.exe to PATH"** in the installer.
- Roblox Studio with access to the place (Team Create invite).

## Play

1. Download this repo (green **Code** button → **Download ZIP**) and unzip it anywhere, or `git clone` it.
2. Double-click **`start_server.bat`**. The first run installs the Python packages (about a minute).
   Leave the window open; it says `Serving ...` when ready.
3. Open the place in Roblox Studio and press **Play**.
4. You get an **Apps** desktop — pick **Browser** (web browsing + URL bar) or **GTA V** (the game stream).
   **← Apps** returns to the launcher. In GTA, click to capture the mouse, **Esc** releases it.

Game sound plays through the PC's default speakers/headset (it comes from the hidden Edge window, so it shows up as
"Microsoft Edge" in the Windows volume mixer if you want to adjust or mute it).

The first load takes 1–3 minutes while the game downloads its data; after that it is cached in
`.capture-profile\` next to the scripts, so later starts are much faster.

## One-time Studio settings (already set in the shared place; only if you make your own)

- Game Settings → Security → **Allow HTTP Requests** (needed to reach the local server).
- Game Settings → Security → **Allow Mesh / Image APIs** (needed for the sharp 1024×576 display;
  without it you get a low-resolution fallback and an orange notice in the corner).

## If something goes wrong

| Symptom | Fix |
| --- | --- |
| Roblox shows "capture failed" or "PC out of memory" | Close other apps (Discord, extra browser tabs), then reopen `start_server.bat`. |
| Loading screen stuck for minutes | Open <http://127.0.0.1:8765/roblox-gpu/reload> in a browser: restarts the game tab without restarting the server. |
| Black screen, no status text | The server is not running; `start_server.bat` must stay open. |
| Checkerboard or "LOW QUALITY" | Enable **Allow Mesh / Image APIs** (see above) and press Play again. |

Log of the last run: the `start_server.bat` window (also `serve.log` when started via `restart_gpu_server.ps1`).

## Configuration

`roblox-port/GpuConfig.lua` (inside the place under `ReplicatedStorage.GTA_WebPort.GpuConfig`) holds the
stream settings: `SOURCE_URL` (original site or a local mirror), `WIDTH`/`HEIGHT` (max 1024 per side),
`FPS` (capped at 8 — Roblox allows only 500 HttpService requests/minute; higher FPS freezes every ~25 s),
and `COLOR_DROP_BITS` (bandwidth vs. colour depth). Input is piggybacked on each frame POST so it does
not burn a second request.

## What is in here

- `serve.py` — local HTTP server: `/roblox-gpu/frame` (zstd-compressed RGBA frames), `/roblox-gpu/input` (keyboard/mouse), `/roblox-gpu/reload`, `/roblox-gpu/eval` (diagnostics).
- `roblox_gpu/` — headless Edge capture (Playwright + CDP), input bridge, `page_shim.js` injected into the game page.
- `roblox-port/*.lua` — the Roblox scripts that live in the place (reference copy).
- `start_server.bat` — installs dependencies on first run and starts the server. `restart_gpu_server.ps1` does the same from PowerShell with a log file.
