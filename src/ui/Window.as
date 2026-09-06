// Status + control window and the Openplanet menu entry.
//
// Connection details are edited here (they still persist via the S_* settings,
// so the Openplanet Settings tab keeps working too). Fields are locked while a
// session is live.

[Setting hidden]
bool S_WindowOpen = true;

void RenderMenu() {
    if (UI::MenuItem("\\$5cf Archipelago", "", S_WindowOpen)) {
        S_WindowOpen = !S_WindowOpen;
    }
}

void RenderInterface() {
    if (!S_WindowOpen || g_client is null) return;

    UI::SetNextWindowSize(360, 340, UI::Cond::FirstUseEver);
    if (UI::Begin("Archipelago", S_WindowOpen)) {
        RenderStatusLine();
        UI::Separator();
        RenderConnectionForm();
        UI::Separator();
        RenderProgress();
    }
    UI::End();
}

void RenderStatusLine() {
    string label;
    switch (g_client.Phase) {
        case Ap::Phase::Disconnected: label = "\\$888Disconnected";   break;
        case Ap::Phase::Ready:        label = "\\$3f5Connected";      break;
        case Ap::Phase::Error:        label = "\\$f55Error";          break;
        default:                      label = "\\$fd5Connecting...";   break;
    }
    UI::Text(label);
    if (g_client.Phase == Ap::Phase::Error) {
        UI::TextWrapped("\\$f77" + g_client.LastError);
    } else if (g_client.IsReady) {
        UI::Text("Seed: " + g_client.seedName);
    }
}

void RenderConnectionForm() {
    bool busy = g_client.Phase != Ap::Phase::Disconnected
             && g_client.Phase != Ap::Phase::Error;

    UI::BeginDisabled(busy);
    UI::PushItemWidth(200);
    S_Host     = UI::InputText("Host", S_Host);
    S_Port     = UI::InputInt("Port", S_Port);
    S_UseTls   = UI::Checkbox("Use TLS (wss://)", S_UseTls);
    S_SlotName = UI::InputText("Slot name", S_SlotName);
    S_Password = UI::InputText("Password", S_Password, UI::InputTextFlags::Password);
    UI::PopItemWidth();
    UI::EndDisabled();

    if (!busy) {
        UI::BeginDisabled(S_SlotName.Length == 0);
        if (UI::Button("Connect")) startnew(CoroutineFunc(g_client.Connect));
        UI::EndDisabled();
    } else {
        if (UI::Button("Disconnect")) g_client.Disconnect();
    }
    UI::SameLine();
    UI::BeginDisabled(!g_client.IsReady);
    if (UI::Button("Report goal")) g_client.ReportGoal();
    UI::EndDisabled();
}

void RenderProgress() {
    if (!g_client.IsReady) return;
    auto loc = g_client.locations;
    float frac = loc.TotalCount > 0 ? float(loc.CheckedCount) / loc.TotalCount : 0;
    UI::ProgressBar(frac, vec2(-1, 0), loc.CheckedCount + " / " + loc.TotalCount + " checks");
    UI::Text("Tracks unlocked: " + g_client.items.UnlockedTrackCount());

    string labelName = g_gameState !is null ? g_gameState.CurrentTrackLabel : "";
    if (labelName != "") {
        bool unlocked = g_client.items.IsTrackUnlocked(labelName);
        UI::Text("Current: " + labelName
                 + (unlocked ? "  \\$3f3[unlocked]" : "  \\$f33[locked]"));
    }
}
