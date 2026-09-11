# Plugin assets

Runtime files the plugin loads by plugin-relative path
(`Audio::LoadSample("assets/…")`, `nvg::LoadTexture("assets/…")`).

## Medal ceremony sounds — NATIVE ONLY, not shipped

`src/ui/MedalSplash.as` plays these on a finish that earns a check (`S_MedalSound`):

| File                             | Plays when                                             |
|----------------------------------|--------------------------------------------------------|
| `assets/voice-medal-bronze.wav`  | reserved -- no current trigger (see below)             |
| `assets/voice-medal-silver.wav`  | reserved -- no current trigger (see below)             |
| `assets/voice-medal-gold.wav`    | a finish earns a check with a Gold run                 |
| `assets/voice-medal-author.wav`  | a finish earns a check with an Author run (Author wins when the run also cleared Gold) |

A Bronze/Silver *finish* is silent. There used to be a second trigger — a
received Bronze/Silver/Gold medal *item* playing that tier's line — but the
apworld now sends a single ungraded "Progressive Medal" item (see
`ItemManager.as`), so there's no tier to announce on receipt. Dropped until
`unlock_style: real_medals` reintroduces per-grade items; the bronze/silver
files stay reserved for that.

These are the game's own announcer voice lines, extracted from the Turbo packs
(44.1 kHz mono 16-bit PCM WAV — `Audio::LoadSample` reads them directly, `bext` /
`JUNK` ancillary chunks and all). If a file is absent that tier's splash is
silent — there is no placeholder / synthesised fallback (deliberate: the real
sound or nothing). To swap names/format, edit `MedalSplash::SAMPLE_FILE`.

### Why the plugin can't just play the game's sound

`CGameScriptHandlerPlaygroundInterface::PlayUiSound`,
`CAudioScriptManager::PlaySoundLibrary` / `PlaySoundEvent*`,
`CGameManiaplanetPlugin::PlaySound` are all ManiaScript-only (`"t":1`) — not
callable from an Openplanet plugin. The sound data itself lives as
`CPlugSound` / `CPlugFileSnd` inside the encrypted `NadeoPak` archives, which
`Audio::LoadSample` cannot open. So the only way to get the native jingle is to
extract the `.ogg` yourself and drop it in here.

### Where to get the files

Trackmania Turbo packs (Steam):
`…\steamapps\common\Trackmania Turbo\Packs\` — all `NadeoPak` v18, encrypted
headers, so plain unzip / `strings` won't work. Use a NadeoPak tool that has the
Turbo keys built in:

- **GbxPakExplorer** (browser, no install) — <https://schadocalex.github.io/GbxPakExplorer/>.
  Drag a `.pak` in, browse the tree, download individual files.
- **GBX.NET 2** (`Gbx.NET.PAK`) if you want to script it.

Look in this order:

1. `Packs\ManiaPlanet.pak` → **`Media\Sounds\…`** — the engine "library" sounds
   that back `PlaySoundLibrary(ELibSound::…)`. `ELibSound` on this build is
   `{Alert, ShowDialog, HideDialog, ShowMenu, HideMenu, Focus, Valid, Start,
   Countdown, Victory, ScoreIncrease, Checkpoint}` — **`Victory*`** is the
   medal / new-record jingle. Also grab `ScoreIncrease*` (the medal-pip count-up)
   if you want a pre-roll.
2. `Packs\TMTurbo.Title.Pack.Gbx` (the Turbo title, ~850 MB) → `Media\Sounds\…`
   and `Media\Sound\…` — Turbo's campaign has its own reward ceremony; if there
   are per-medal cues (bronze/silver/gold/author) they're here, likely named for
   the medal or under a `Podium` / `Reward` / `EndRace` folder.
3. `Packs\Resource.pak` → small, engine UI sounds — worth a look for
   `Record` / `Finish`.

`EUISound` (the `PlayUiSound` enum) has a `Record` and a `Finish` entry but **no
Bronze/Silver/Gold** — Turbo's per-medal distinction comes from the title pack,
not the core UI set. If you only find one "new record" sound, use it for all four
names (copy the file 4×) — that already matches what the game does for most
tiers.

Turbo's audio is Ogg Vorbis; `CPlugFileSnd` entries point straight at `.ogg`
blobs, so what you extract should be directly loadable. Trim/normalise if needed.

### Alternative: let the plugin extract it at runtime

Openplanet can read the decrypted VFS: `Fids::GetGame("Media\\Sounds\\…\\X.ogg")`
→ `Fids::Extract(fid)` dumps the real bytes to disk, then
`Audio::LoadSampleFromAbsolutePath(...)`. This needs the exact in-pack path
string — not wired up yet; `MedalSplash.as` has a `TODO` where it would go. If
you'd rather go this route than hunt through the pak, say so and it can be built
with a one-time in-game folder scan to discover the path.
