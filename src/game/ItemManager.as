// Applies items the server sends us (ReceivedItems) to the local game state.
//
// Turbo has no runtime API to lock/unlock campaign tracks, so "unlocks" are
// enforced by the plugin: ItemManager owns the set of unlocked track labels and
// GameState / the UI consult it. Persisted per seed so a restart mid-run keeps
// your unlocks without a server round-trip (the Sync on reconnect reconciles).

class ItemManager {
    private ApClient@ m_client;

    private int m_nextIndex = 0;             // ReceivedItems cursor
    private dictionary m_unlockedTracks;     // label -> true
    private dictionary m_itemCounts;         // itemName -> int (for progressive / filler)

    ItemManager(ApClient@ client) { @m_client = client; }

    void Reset() {
        m_nextIndex = 0;
        m_unlockedTracks.DeleteAll();
        m_itemCounts.DeleteAll();
    }

    bool IsTrackUnlocked(const string &in label) const {
        return m_unlockedTracks.Exists(label);
    }
    int UnlockedTrackCount() const { return m_unlockedTracks.GetSize(); }
    int ItemCount(const string &in name) const {
        int64 n = 0; m_itemCounts.Get(name, n); return int(n);
    }

    void OnReceivedItems(Json::Value@ cmd) {
        int index = cmd["index"];
        Json::Value@ arr = cmd["items"];
        Log::Trace("ReceivedItems index=" + index + " count=" + arr.Length
                   + " (m_nextIndex=" + m_nextIndex + ")");

        // index 0 == full replay (response to Sync). Reset local view first.
        if (index == 0) {
            m_unlockedTracks.DeleteAll();
            m_itemCounts.DeleteAll();
            m_nextIndex = 0;
        } else if (index != m_nextIndex) {
            // Gap: our cursor is stale. Ask for a full replay.
            Log::Warn("item index gap (" + index + " != " + m_nextIndex + "), re-syncing");
            m_client.transport.Send(Packet::Sync());
            return;
        }

        for (uint i = 0; i < arr.Length; i++) {
            int itemId = arr[i]["item"];
            Apply(m_client.data.ItemName(itemId));
        }
        m_nextIndex = index + arr.Length;
        Persist();
        CheckGoal();
    }

    private void Apply(const string &in itemName) {
        // Convention: track unlock items are named "Unlock: <Track Label>".
        if (itemName.StartsWith("Unlock: ")) {
            string label = itemName.SubStr(8);
            m_unlockedTracks.Set(label, true);
            Log::Info("Unlocked " + label);
            return;
        }
        // Everything else is counted (progressive series unlocks, filler, traps).
        // Use the int64 Get/Set overloads explicitly -- the generic dictionary
        // ?&out path does not reliably round-trip a 32-bit int on this build.
        int64 count = 0;
        m_itemCounts.Get(itemName, count);
        count += 1;
        m_itemCounts.Set(itemName, count);
        Log::Info("Received " + itemName + " (x" + count + ")");
        ApplyProgressive(itemName, int(count));
    }

    private void ApplyProgressive(const string &in itemName, int count) {
        // e.g. "Progressive White" -> unlock the first N White tracks in campaign
        // order (White Canyon 01, .. 10, White Valley 01, ..) as count grows.
        if (!itemName.StartsWith("Progressive ")) return;
        string tier = itemName.SubStr(12);
        string label = TierTrackLabel(tier, count);
        if (label == "") return;
        m_unlockedTracks.Set(label, true);
        Log::Info("Progressive unlock: " + label);
    }

    // Goal: configurable. Default here -- every location checked.
    private void CheckGoal() {
        if (!S_AutoGoal || !m_client.IsReady) return;
        auto loc = m_client.locations;
        if (loc.TotalCount > 0 && loc.CheckedCount >= loc.TotalCount) {
            m_client.ReportGoal();
        }
    }

    // ---- persistence (per seed) -------------------------------------
    private string StatePath() {
        return IO::FromStorageFolder("seed-" + m_client.seedName + ".json");
    }
    private void Persist() {
        Json::Value@ root = Json::Object();
        root["nextIndex"] = m_nextIndex;
        Json::Value@ tracks = Json::Array();
        array<string>@ keys = m_unlockedTracks.GetKeys();
        for (uint i = 0; i < keys.Length; i++) tracks.Add(Json::Value(keys[i]));
        root["unlocked"] = tracks;
        Json::ToFile(StatePath(), root);
    }
    void LoadState() {
        if (m_client.seedName == "" || !IO::FileExists(StatePath())) return;
        Json::Value@ root = Json::FromFile(StatePath());
        if (root is null) return;
        m_nextIndex = root["nextIndex"];
        Json::Value@ tracks = root["unlocked"];
        for (uint i = 0; i < tracks.Length; i++) m_unlockedTracks[string(tracks[i])] = true;
    }
}
