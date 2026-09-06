# CLAUDE.md — Archipelago plugin for Trackmania Turbo

Guidance for Claude Code / contributors working in this repo.

## What this is

An Openplanet (AngelScript) plugin bridging **Trackmania Turbo** and the
**Archipelago** multiworld randomizer. Finishing a run on an official campaign
track becomes an Archipelago *location check*; *items* received from the
multiworld unlock campaign tracks, enforced client-side because Turbo exposes no
unlock API.

The server side is a separate `trackmania_turbo` **.apworld** (not in this repo).
The strings in "Naming contract" below are what the two halves agree on.

## Build / run / test

There is no compiler or test runner. **Build = reload:**
`Openplanet > Developer > Reload plugin`. Compile errors and `print`/`warn`/
`error` output go to the Openplanet log window and
`%USERPROFILE%\OpenplanetTurbo\Openplanet.log` (which flushes lazily — reload to
force it). Turn on `Settings > Archipelago > Debug > Verbose protocol logging`
(`S_Trace`) for per-frame tracing.

Dev install — symlink this folder into the plugins dir:

```
cmd /c mklink /D "%USERPROFILE%\OpenplanetTurbo\Plugins\Archipelago" "%CD%"
```

Manual testing: run a local `ArchipelagoServer` (or `MultiServer.py`) hosting a
`Trackmania Turbo` world on `localhost:38281`, connect the plugin (`ws://`, TLS
off), and exercise flows in-game. A `ArchipelagoTextClient` on the same slot is a
useful independent observer.

Style: 4-space indent, `PascalCase` methods, `m_` private fields, `S_` settings,
`g_` globals. No linter — match the surrounding file.

## Architecture

Data flows in two directions, meeting at `ApClient`:

```
game thread (Update)                     client coroutine (Main loop)
  GameState.Update()                        ApClient.Update()
    reads CGameCtnApp nod                     transport.Pump()  -> inbound frames
    emits FinishEvent on a race finish        Packet::Parse + Dispatch
        │                                        ├─ Connected     -> LocationManager.SeedFromServer
        ▼                                        └─ ReceivedItems -> ItemManager.OnReceivedItems
  LocationManager.OnFinish  ──────────────►         │
    TrackTable: map number -> label                 ▼
    DataPackage: name -> id                   ItemManager: client-enforced unlock set
    ApClient.SendLocationChecks ──► transport
```

Key seams: **all engine access is confined to `src/game/GameState.as`**, **all
socket access to `src/net/Transport.as`**. Everything else is pure data transform
and reasons without the game or a server.

### Threading

`Update(float dt)` is called by Openplanet on the **game thread** — the only safe
place to touch `GetApp()` / engine nods. `Main()` runs a coroutine doing network
+ JSON only. Cross-thread hand-off is one nullable field: `GameState.pendingFinish`,
produced and consumed in `Update` (same thread). Don't call into `GameState` from
the coroutine; don't touch engine nods from `ApClient` / managers.

### Networking

The Turbo Openplanet build (1.29.x) has **no `Net::WebSocket`**. `Transport.as`
is a minimal RFC 6455 client over `Net::Socket` (which supports TLS via
`Connect(host, port, secure)`): HTTP upgrade handshake, masked text frames out,
unmasked + fragmented + ping/pong in. Nothing outside this file knows WebSocket
exists.

The receive buffer is `array<uint8>`, **not `string`** — `Net::Socket.ReadRaw`
and AngelScript string concat truncate at the first `0x00`, and WebSocket frame
length headers contain zero bytes (any payload length that is a multiple of 256).
Read via `Socket.ReadBuffer` → `MemoryBuffer`; only turn a NUL-free JSON payload
into a `string`.

### Openplanet Turbo API traps

- **`dictionary` has no `Get(string, int&out)`** — only `int64&out`, `double&out`,
  generic `?&out`. The generic path does not round-trip a 32-bit `int` (returns
  stale values). Always use `int64` with dictionary number values; prefer
  `.Set(k, v)` over `d[k] = v`.
- **`CGameCtnChallengeInfo.Medal` / `.BestTime` are blank for campaign maps**
  (`EMedal=0`, `BestTime=0xFFFFFFFF`). No saved solo progress there. `GameState`
  reads the finish from `CTrackManiaPlayer.RaceState` (`app.CurrentPlayground.
  GameTerminals[0].ControlledPlayer`) → on the edge into `Finished`, the time from
  `CurRace.Time` (poll a few ticks — not ready the instant the state flips),
  medal from `challenge.TMObjective_{Bronze,Silver,Gold,Author}Time`.
- Campaign map identity: `challenge.MapName` is `"001".."200"`,
  `challenge.AuthorLogin == "Nadeo"` — no UID table. Same method the Ultimate
  Medals plugin uses (`Phlarx/tm-ultimate-medals`).

Grep `%USERPROFILE%\OpenplanetTurbo\OpenplanetCore.json` (script API) and
`Openplanet.h` (engine nods) before assuming a class or method exists — much of
the online Openplanet docs describe the newer TM2020 build.

- **No `Draw::` namespace.** Screen drawing is `nvg::` (only from a global
  `void Render()` — drawn even with the Openplanet overlay closed) or
  `UI::Get*DrawList()`.
- **The campaign overlay** (`src/ui/CampaignOverlay.as`, the plugin's only
  `Render()`): no menu API, so it walks the Nadeo ManiaLink tree via
  `cast<CTrackManiaMenus>(app.MenuManager).MenuCustom_CurrentManiaApp`.
  - **Series-overview grid** (200 tiles): shown when `UILayers[12].IsVisible`
    *and* layer 11's `Frame_AllBrowseTrack` is hidden. Tile geometry from layer
    11: find frame `ControlId == "FrameAll_Buttons"`, its `Frame_Instance*`
    children are the 200 tiles (row-major); map number from the
    `MouseInput_Track_<R>:<C>` child
    (`n = (R/2)*40 + (C/5)*10 + (R%2)*5 + (C%5) + 1`), position from
    `AbsolutePosition_V3` (ML; tile `48.21 × 45.0`, `y` up). Layer 12's own tiles
    use opaque ids; layer 11's positions coincide with layer 12's render.
  - **Per-series track picker** (10 thumbnails): shown when layer 11's
    `Frame_AllBrowseTrack.Visible`. Those tiles aren't reachable; read the series
    from `FrameAll_Buttons.Controls[3]` (`Label_Diff0`) text and the environment
    from which column `Frame_Selector` sits in, then draw at 10 fixed slots.
  - layer 11's own `IsVisible` / frame-visible flags are IDENTICAL between the
    series grid and the main menu — only `UILayers[12].IsVisible` /
    `Frame_AllBrowseTrack.Visible` disambiguate the three states.
- **ML → screen has no exposed transform** on this build (menu mouse coords
  `CGameManiaApp.MouseX/Y` are a *different* space — do not use them). Both grids
  are mapped into a screen rect given as window fractions (`S_GridL/T/R/B` for the
  200-grid, `S_TpL/T/R/B` for the picker), calibrated once by eye with the Debug
  "Overlay alignment" sliders + box-preview, and persisted. Re-tune per
  resolution/aspect.
- **Writing Nadeo ManiaLink control fields does NOT stick.** Every tile has a
  hidden native `Quad_Locked` (`locked-2x2.dds`); setting `.Visible = true` on it
  executes but the menu's own script re-hides it the same frame, so it never
  renders. No MLHook for Turbo. Overlays must be *drawn* (`nvg`), not injected.

### Archipelago protocol notes

- Frames are JSON **arrays** of command objects (`Packet::WrapArray` / `Parse`).
- Handshake: `RoomInfo` → (`GetDataPackage` if checksum changed) → `Connect`
  (`items_handling = 7`, `slot_data = true`) → `Connected` | `ConnectionRefused`.
- On `Connected` the client sends `Sync` (replay all items so reconnects restore
  unlocks) then `StatusUpdate(Playing)`.
- `ReceivedItems.index == 0` = full replay — reset local item state first. A
  non-zero `index != m_nextIndex` = a gap → send `Sync`.
- Location sends are optimistic; `RoomUpdate.checked_locations` is the confirmation.

### Files

| File | Responsibility |
|------|----------------|
| `src/Main.as` | Lifecycle, globals (`g_client`, `g_gameState`), per-frame wiring |
| `src/Settings.as` | `[Setting]` vars, `Medal` enum, `ServerUrl()` |
| `src/Log.as` | Logging facade; `Log::Trace` gated on `S_Trace` |
| `src/net/Transport.as` | Hand-rolled WebSocket: connect / `Pump()` / `Send()` / close |
| `src/ap/Protocol.as` | AP constants, packet builders, frame parser (`Packet::`) |
| `src/ap/DataPackage.as` | Server id ⇄ name maps, disk-cached by checksum |
| `src/ap/ApClient.as` | Session state machine (`Ap::Phase`), handshake, dispatch |
| `src/game/GameState.as` | Reads the Turbo nods; emits `FinishEvent` on a race finish; bounces the player out of locked tracks |
| `src/game/TrackTable.as` | Campaign map number (1–200) ⇄ `"<Tier> <Env> NN"` label |
| `src/game/LocationManager.as` | finish → location id; dedupe; batched send; per-track checked-medal mask |
| `src/game/ItemManager.as` | consumes `ReceivedItems`; client-enforced unlock set; per-seed persistence |
| `src/ui/Window.as` | Status window + `RenderMenu()` entry |
| `src/ui/CampaignOverlay.as` | `Render()` — nvg lock / medal-pip markers on the series grid *and* the per-series track picker |

## Naming contract with the `.apworld`

If you change one of these, change it on both sides.

- Game name: `"Trackmania Turbo"` (`AP_GAME_NAME` in `Protocol.as`).
- Track label: `"<Tier> <Environment> NN"`, e.g. `"White Canyon 01"`.
  Tier ∈ {White, Green, Blue, Red, Black} (difficulty order).
  Environment ∈ {Canyon, Valley, Lagoon, Stadium}. NN = 01..10. 200 tracks total.
  Campaign map number 1..200 → these difficulty-major, then environment, then NN
  (`TrackLabel` in `TrackTable.as`).
- Location: `"<Track Label> - <Medal>"`, e.g. `"White Canyon 01 - Gold"`.
  Medal ∈ {Bronze, Silver, Gold, Author}.
- Track-unlock item: `"Unlock: <Track Label>"`.
- Progressive-unlock item: `"Progressive <Tier>"` — unlocks that tier's 40 tracks
  in campaign order (Canyon 01..10, Valley 01..10, Lagoon 01..10, Stadium 01..10).

## Open items

- **Track-lock enforcement UX — done, verified in-game (1920×1080).**
  `CampaignOverlay.as` marks locked tracks with a padlock on both the series grid
  and the track picker (unlocked tracks get Bronze/Silver/Gold/Author pips for
  checked medals); `GameState.LockedNow()` calls `BackToMainMenu()` when the
  player loads a locked campaign map (`S_BlockLockedTracks`) — confirmed it lands
  cleanly and writes no time. Only remaining: the grid-rect / picker-slot
  calibration is per-resolution (re-tune with the Debug sliders on other setups).
- **Goal condition.** `ItemManager.CheckGoal()` fires on "all locations checked".
  It should read the goal from `slot_data` instead (the apworld sends `goal`).
- **Medal-detection breadth.** Verified for one track; spot-check the finish
  signal and `CurRace.Time` on a few more, and whether solo always passes through
  `RaceState == Finished` (fallback: `CGamePlaygroundScript.Solo_NewRecordSequenceInProgress`).
- **`wss://` path.** Only `ws://` (local) is exercised so far; test TLS +
  fragmented inbound frames against `archipelago.gg`.
- Debug traces in `GameState` / `LocationManager` / `ItemManager` / `Transport`
  are gated on `S_Trace` and can be trimmed once bring-up settles.
