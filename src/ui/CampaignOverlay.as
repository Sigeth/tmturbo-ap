// Draws lock / medal-progress markers straight onto Turbo's campaign map grid,
// one per tile, for all 200 campaign tracks.
//
// Turbo has no menu API, so we walk the Nadeo ManiaLink tree: find
// "FrameAll_Buttons" (in UILayers[11], the campaign grid), iterate its
// "Frame_Instance*" tile children, read each tile's map number from its
// "MouseInput_Track_<row>:<col>" child, and take its position from
// AbsolutePosition_V3 (ManiaLink coordinate space).
//
// The ManiaLink tile grid occupies a fixed rectangle in ML space (measured
// in-game): x in [-120.28, 843.74], y in [25.80, -424.20] (y is up). We map that
// rectangle onto a screen rectangle given as window fractions (S_GridL/T/R/B),
// tuned once by eye via the Debug "Overlay alignment" sliders (box-preview mode)
// and persisted. Re-tune for a different resolution/aspect. There is no reliable
// ML->pixel transform exposed by this build (menu mouse coords are a different
// space), hence the manual calibration.
//
// This is the plugin's only Render(); nvg may only be used here. Every cast is
// null-guarded -- an unrecognised menu just shows nothing.

namespace Overlay {
    const float PI = 3.14159265;
    const float TILE_W = 48.21;
    const float TILE_H = 45.0;

    // ML-space extent of the tile grid (col 0 left / col 19 right, row 0 top /
    // row 9 bottom). From the probe.
    const float GRID_L = -120.28;
    const float GRID_R = 843.74;
    const float GRID_T = 25.80;
    const float GRID_B = -424.20;

    const array<vec4> MEDAL_COL = {
        vec4(0, 0, 0, 0),
        vec4(0.71, 0.40, 0.16, 1),   // Bronze
        vec4(0.75, 0.75, 0.78, 1),   // Silver
        vec4(1.00, 0.82, 0.25, 1),   // Gold
        vec4(0.20, 0.76, 0.42, 1)    // Author
    };

    vec2 ToScreen(float mlx, float mly) {
        float w = float(Display::GetWidth());
        float h = float(Display::GetHeight());
        float fx = (mlx - GRID_L) / (GRID_R - GRID_L);        // 0..1 left..right
        float fy = (GRID_T - mly) / (GRID_T - GRID_B);        // 0..1 top..bottom
        return vec2((S_GridL + fx * (S_GridR - S_GridL)) * w,
                    (S_GridT + fy * (S_GridB - S_GridT)) * h);
    }

    // ---- ManiaLink tree walk ----------------------------------------------
    CGameManialinkFrame@ FindFrameById(CGameManialinkControl@ node, const string &in id, int depth) {
        if (node is null || depth > 16) return null;
        auto frame = cast<CGameManialinkFrame>(node);
        if (frame is null) return null;
        if (frame.ControlId == id) return frame;
        for (uint i = 0; i < frame.Controls.Length; i++) {
            auto hit = FindFrameById(frame.Controls[i], id, depth + 1);
            if (hit !is null) return hit;
        }
        return null;
    }

    CGameManialinkFrame@ TilesFrame(CGameManiaAppTitle@ m) {
        if (m is null) return null;
        for (uint pass = 0; pass < m.UILayers.Length + 1; pass++) {
            uint li = (pass == 0) ? 11 : (pass - 1);
            if (li >= m.UILayers.Length) continue;
            auto layer = cast<CGameUILayer>(m.UILayers[li]);
            if (layer is null || layer.LocalPage is null) continue;
            auto hit = FindFrameById(layer.LocalPage.MainFrame, "FrameAll_Buttons", 0);
            if (hit !is null && hit.Controls.Length > 20) return hit;
        }
        return null;
    }

    // "MouseInput_Track_R:C" -> 1..200, or 0.
    int MapNumber(CGameManialinkFrame@ tile) {
        for (uint i = 0; i < tile.Controls.Length; i++) {
            auto c = tile.Controls[i];
            if (c is null || !c.ControlId.StartsWith("MouseInput_Track_")) continue;
            array<string>@ parts = c.ControlId.Split("_");
            array<string>@ rc = parts[parts.Length - 1].Split(":");
            if (rc.Length != 2) return 0;
            int r = 0, col = 0;
            if (!Text::TryParseInt(rc[0], r) || !Text::TryParseInt(rc[1], col)) return 0;
            if (r < 0 || r > 9 || col < 0 || col > 19) return 0;
            return (r / 2) * 40 + (col / 5) * 10 + (r % 2) * 5 + (col % 5) + 1;
        }
        return 0;
    }

    // ---- drawing (screen rect: x,y top-left, w,h > 0) --------------------
    void DrawBox(float x, float y, float w, float h, const vec4 &in col) {
        nvg::BeginPath();
        nvg::Rect(x, y, w, h);
        nvg::StrokeColor(col);
        nvg::StrokeWidth(1.5f);
        nvg::Stroke();
    }

    void DrawLock(float x, float y, float w, float h) {
        nvg::BeginPath();
        nvg::RoundedRect(x, y, w, h, w * 0.10f);
        nvg::FillColor(vec4(0, 0, 0, 0.55));
        nvg::Fill();

        float s = Math::Min(w, h);
        float cx = x + w * 0.5f;
        float cy = y + h * 0.5f;
        float body = s * 0.30f;
        float rad  = s * 0.14f;

        nvg::BeginPath();
        nvg::Arc(vec2(cx, cy - body * 0.35f), rad, PI, 2 * PI, nvg::Winding::CW);
        nvg::StrokeColor(vec4(1, 1, 1, 0.95));
        nvg::StrokeWidth(Math::Max(2.0f, s * 0.05f));
        nvg::Stroke();

        nvg::BeginPath();
        nvg::RoundedRect(cx - body * 0.55f, cy - body * 0.35f, body * 1.1f, body * 0.9f, body * 0.15f);
        nvg::FillColor(vec4(1, 1, 1, 0.95));
        nvg::Fill();

        nvg::BeginPath();
        nvg::Circle(vec2(cx, cy + body * 0.05f), Math::Max(1.5f, s * 0.035f));
        nvg::FillColor(vec4(0, 0, 0, 0.85));
        nvg::Fill();
    }

    void DrawPips(float x, float y, float w, float h, int mask) {
        float r = Math::Max(2.5f, Math::Min(w, h) * 0.075f);
        float gap = r * 2.6f;
        float total = gap * 3;
        float px = x + w * 0.5f - total * 0.5f;
        float py = y + h - r * 2.2f;
        for (int t = 1; t <= 4; t++) {
            vec2 c = vec2(px + (t - 1) * gap, py);
            bool got = (mask & (1 << t)) != 0;
            nvg::BeginPath();
            nvg::Circle(c, r);
            if (got) {
                nvg::FillColor(MEDAL_COL[t]);
                nvg::Fill();
                nvg::StrokeColor(vec4(0, 0, 0, 0.5));
                nvg::StrokeWidth(1.0f);
                nvg::Stroke();
            } else {
                nvg::StrokeColor(vec4(MEDAL_COL[t].x, MEDAL_COL[t].y, MEDAL_COL[t].z, 0.5));
                nvg::StrokeWidth(1.5f);
                nvg::Stroke();
            }
        }
    }
}

void Render() {
    if (!S_CampaignOverlay) return;
    if (g_client is null || !g_client.IsReady) return;

    auto app = cast<CTrackMania>(GetApp());
    if (app is null || app.Challenge !is null) return;         // only in menus
    auto menu = cast<CTrackManiaMenus>(app.MenuManager);
    if (menu is null) return;
    auto m = menu.MenuCustom_CurrentManiaApp;
    if (m is null) return;

    auto tiles = Overlay::TilesFrame(m);
    if (tiles is null) return;

    float sw = float(Display::GetWidth());
    float sh = float(Display::GetHeight());

    for (uint i = 0; i < tiles.Controls.Length; i++) {
        auto tile = cast<CGameManialinkFrame>(tiles.Controls[i]);
        if (tile is null || !tile.Visible || !tile.ControlId.StartsWith("Frame_Instance")) continue;

        int n = Overlay::MapNumber(tile);
        if (n < 1 || n > 200) continue;
        string label = TrackLabel(n);

        vec2 ml = tile.AbsolutePosition_V3;                       // ML top-left
        vec2 tl = Overlay::ToScreen(ml.x, ml.y);
        vec2 br = Overlay::ToScreen(ml.x + Overlay::TILE_W, ml.y - Overlay::TILE_H);
        float x = Math::Min(tl.x, br.x);
        float y = Math::Min(tl.y, br.y);
        float w = Math::Abs(br.x - tl.x);
        float hgt = Math::Abs(br.y - tl.y);
        if (w < 3 || hgt < 3 || x > sw || y > sh || x + w < 0 || y + hgt < 0) continue;

        if (S_GridDebug) {
            Overlay::DrawBox(x, y, w, hgt, vec4(1, 0, 1, 0.9));
            continue;
        }
        if (g_client.items.IsTrackUnlocked(label)) {
            Overlay::DrawPips(x, y, w, hgt, g_client.locations.CheckedMedalMask(label));
        } else {
            Overlay::DrawLock(x, y, w, hgt);
        }
    }
}
