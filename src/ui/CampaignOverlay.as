// Draws lock / medal-progress markers straight onto Turbo's campaign
// map-selection screen, so the player can see at a glance which tracks the
// multiworld has unlocked.
//
// Turbo has no menu API. The only way to know which tier/environment page is on
// screen is to walk the Nadeo ManiaLink UI tree. The layer index (11), the
// Controls[...] path and the -120 selected-tab x position are all lifted from
// the TurboSkillpoints plugin, which does the same thing and is known to work on
// this Openplanet build (1.29.14 turbo). Every cast is null-guarded: a menu
// revision that reshapes the tree just makes the overlay disappear, never crash.
//
// Screen positions are hard-coded 16:9 fractions (also from TurboSkillpoints);
// on other aspect ratios the markers drift -- documented, not fixed.
//
// This is the plugin's only `Render()` (drawn every frame, even with the
// Openplanet overlay closed). `nvg` may only be used from here.

namespace Overlay {
    const float PI = 3.14159265;

    // 10 map tiles: two rows of five. Anchor = top-left-ish of each tile, in
    // fractions of the screen (denominator form kept from TurboSkillpoints).
    const array<float> COL_DIV = { 7.875, 3.585, 2.335, 1.730, 1.370 };
    const float ROW1_DIV = 1.766;
    const float ROW2_DIV = 1.226;

    // Medal pip colours, indexed by Medal enum (1..4); [0] unused.
    const array<vec4> MEDAL_COL = {
        vec4(0, 0, 0, 0),
        vec4(0.71, 0.40, 0.16, 1),   // Bronze
        vec4(0.75, 0.75, 0.78, 1),   // Silver
        vec4(1.00, 0.82, 0.25, 1),   // Gold
        vec4(0.20, 0.76, 0.42, 1)    // Author
    };

    vec2 SlotAnchor(uint i) {
        float w = float(Display::GetWidth());
        float h = float(Display::GetHeight());
        float x = w / COL_DIV[i % 5];
        float y = h / (i < 5 ? ROW1_DIV : ROW2_DIV);
        return vec2(x, y);
    }

    CGameManialinkControl@ Child(CGameManialinkControl@ c, uint idx) {
        auto frame = cast<CGameManialinkFrame>(c);
        if (frame is null || idx >= frame.Controls.Length) return null;
        return frame.Controls[idx];
    }

    // Resolve the campaign map-selection layer and read which page it shows.
    // Returns the 0-based campaign index of the first visible tile, or -1 if the
    // screen is not currently up / the tree didn't match.
    int VisiblePageStart(CGameManiaAppTitle@ maniaApp) {
        if (maniaApp is null || maniaApp.UILayers.Length < 17) return -1;

        auto layer = cast<CGameUILayer>(maniaApp.UILayers[11]);
        if (layer is null || !layer.IsVisible || layer.LocalPage is null) return -1;
        auto main = layer.LocalPage.MainFrame;
        if (main is null) return -1;

        auto buttons = Child(Child(Child(Child(Child(main, 0), 4), 1), 2), 1);
        auto frameButtons = cast<CGameManialinkFrame>(buttons);
        if (frameButtons is null) return -1;

        auto labelSeries = cast<CGameManialinkLabel>(Child(frameButtons, 3));
        if (labelSeries is null) return -1;

        int series = 0;                                  // 1..5, White..Black
        string v = string(labelSeries.Value);
        if      (v.Contains("White")) series = 1;
        else if (v.Contains("Green")) series = 2;
        else if (v.Contains("Blue"))  series = 3;
        else if (v.Contains("Red"))   series = 4;
        else if (v.Contains("Black")) series = 5;
        if (series == 0) return -1;

        int envi = 0;                                    // 1..4, Canyon..Stadium
        array<uint> envCtl = { 20, 25, 30, 35 };
        for (uint e = 0; e < envCtl.Length; e++) {
            auto f = cast<CGameManialinkFrame>(Child(frameButtons, envCtl[e]));
            if (f !is null && Math::Round(f.AbsolutePosition_V3.x) == -120.0f) { envi = int(e) + 1; break; }
        }
        if (envi == 0) return -1;

        return (envi - 1) * 10 + (series - 1) * 40;      // 0-based first tile
    }

    void DrawLocked(const vec2 &in a) {
        float cx = a.x + 22;
        float cy = a.y + 20;

        nvg::BeginPath();
        nvg::RoundedRect(a.x, a.y - 4, 46, 50, 6);
        nvg::FillColor(vec4(0, 0, 0, 0.60));
        nvg::Fill();

        // shackle (upper half circle)
        nvg::BeginPath();
        nvg::Arc(vec2(cx, cy - 4), 7, PI, 2 * PI, nvg::Winding::CW);
        nvg::StrokeColor(vec4(1, 1, 1, 0.95));
        nvg::StrokeWidth(3.5);
        nvg::Stroke();

        // body
        nvg::BeginPath();
        nvg::RoundedRect(cx - 11, cy - 4, 22, 17, 3);
        nvg::FillColor(vec4(1, 1, 1, 0.95));
        nvg::Fill();

        // keyhole
        nvg::BeginPath();
        nvg::Circle(vec2(cx, cy + 4), 2.4);
        nvg::FillColor(vec4(0, 0, 0, 0.85));
        nvg::Fill();
    }

    void DrawPips(const vec2 &in a, int mask) {
        for (int t = 1; t <= 4; t++) {
            vec2 c = vec2(a.x + 6 + (t - 1) * 13, a.y + 6);
            bool got = (mask & (1 << t)) != 0;
            nvg::BeginPath();
            nvg::Circle(c, 5);
            if (got) {
                nvg::FillColor(MEDAL_COL[t]);
                nvg::Fill();
            } else {
                nvg::StrokeColor(vec4(MEDAL_COL[t].x, MEDAL_COL[t].y, MEDAL_COL[t].z, 0.45));
                nvg::StrokeWidth(1.5);
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

    int pageStart = Overlay::VisiblePageStart(menu.MenuCustom_CurrentManiaApp);
    if (pageStart < 0) return;

    for (uint i = 0; i < 10; i++) {
        string label = TrackLabel(pageStart + int(i) + 1);     // 1-based map number
        if (label == "") continue;
        vec2 a = Overlay::SlotAnchor(i);
        if (g_client.items.IsTrackUnlocked(label)) {
            Overlay::DrawPips(a, g_client.locations.CheckedMedalMask(label));
        } else {
            Overlay::DrawLocked(a);
        }
    }
}
