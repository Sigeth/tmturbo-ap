// Applies items the server sends us (ReceivedItems) to the local game state.
//
// Turbo has no runtime API to lock/unlock campaign tracks, so "unlocks" are
// enforced by the plugin: ItemManager owns the set of unlocked track labels and
// GameState / the UI consult it. Persisted per seed so a restart mid-run keeps
// your unlocks without a server round-trip (the Sync on reconnect reconciles).
//
// Two unlock models, selected by slot_data.unlock_style (see S_UnlockStyle):
//   * item styles ("progressive" / "individual") -- the server sends
//     "Unlock: <Track>" / "Progressive <Tier>" items; m_unlockedTracks is the
//     authoritative set.
//   * "vanilla" -- the server sends "<grade> Medal" items; block i (10 tracks in
//     campaign order) opens once we hold m_blockThresholds[i] items of the
//     block's grade. m_unlockedTracks is unused. Once a block is open, finishing
//     a track sends whatever medal the player actually earned -- no licence.

class ItemManager {
    private ApClient@ m_client;

    private int m_nextIndex = 0;             // ReceivedItems cursor
    private dictionary m_unlockedTracks;     // label -> true  (item styles)
    private dictionary m_itemCounts;         // itemName -> int (progressive / medals / filler)

    // ---- slot_data ----
    private string m_seedUnlockStyle = "";
    private string m_goal = "campaign_finish";
    private array<int> m_blockThresholds;
    private bool m_goalReported = false;

    // Cached vanilla block-unlock state (index 0..19). Recomputed only when medal
    // counts change -- the overlay queries this ~200x/frame.
    private array<bool> m_blockUnlocked;

    ItemManager(ApClient@ client) {
        @m_client = client;
        m_blockUnlocked.Resize(BLOCK_COUNT);
        DefaultBlockThresholds();
        RecomputeBlocks();
    }

    private void DefaultBlockThresholds() {
        m_blockThresholds.Resize(BLOCK_COUNT);
        for (int i = 0; i < BLOCK_COUNT; i++) m_blockThresholds[i] = 10 * i;
    }

    void Reset() {
        m_nextIndex = 0;
        m_unlockedTracks.DeleteAll();
        m_itemCounts.DeleteAll();
        m_goalReported = false;
        m_seedUnlockStyle = "";
        m_goal = "campaign_finish";
        DefaultBlockThresholds();
        RecomputeBlocks();
    }

    // ---- slot_data ---------------------------------------------------
    void OnSlotData(Json::Value@ sd) {
        if (sd is null || sd.GetType() != Json::Type::Object) {
            Log::Info("no slot_data -- using settings / defaults");
            return;
        }
        if (sd.HasKey("unlock_style")) m_seedUnlockStyle = string(sd["unlock_style"]);
        if (sd.HasKey("goal")) m_goal = string(sd["goal"]);
        if (sd.HasKey("block_thresholds")) {
            Json::Value@ bt = sd["block_thresholds"];
            if (bt !is null && bt.GetType() == Json::Type::Array && bt.Length == uint(BLOCK_COUNT)) {
                for (int i = 0; i < BLOCK_COUNT; i++) m_blockThresholds[i] = int(bt[i]);
            }
        }
        Log::Info("slot_data: unlock_style=" + m_seedUnlockStyle + " goal=" + m_goal
                  + " vanilla=" + (VanillaMode() ? "yes" : "no"));
        RecomputeBlocks();
    }

    bool VanillaMode() const {
        if (S_UnlockStyle == UnlockStylePref::ForceVanilla) return true;
        if (S_UnlockStyle == UnlockStylePref::ForceItems) return false;
        return m_seedUnlockStyle == "vanilla";
    }

    // Recompute the 20 cached block-unlock bools from current medal counts.
    void RecomputeBlocks() {
        for (int i = 0; i < BLOCK_COUNT; i++) {
            m_blockUnlocked[i] = i <= 0
                || MedalCount(BlockGrade(i)) >= m_blockThresholds[i];
        }
    }

    string get_Goal() const { return m_goal; }

    // ---- queries ---------------------------------------------------
    bool IsTrackUnlocked(const string &in label) const {
        if (VanillaMode()) return IsTrackUnlockedByNumber(CampaignNumberFromLabel(label));
        return m_unlockedTracks.Exists(label);
    }

    // Cheap path for the overlay (it already has the 1..200 map number).
    bool IsTrackUnlockedByNumber(int campaignNumber) const {
        if (!VanillaMode()) return m_unlockedTracks.Exists(TrackLabel(campaignNumber));
        int b = BlockIndex(campaignNumber);
        if (b <= 0) return true;                          // block 0 / non-campaign
        return m_blockUnlocked[b];
    }

    bool IsBlockUnlocked(int blockIndex) const {
        if (blockIndex <= 0) return true;
        if (blockIndex >= BLOCK_COUNT) return false;
        return m_blockUnlocked[blockIndex];
    }

    int BlockThreshold(int blockIndex) const {
        if (blockIndex < 0 || blockIndex >= BLOCK_COUNT) return 0;
        return m_blockThresholds[blockIndex];
    }

    int UnlockedTrackCount() const {
        if (!VanillaMode()) return m_unlockedTracks.GetSize();
        int n = 0;
        for (int i = 0; i < BLOCK_COUNT; i++) if (IsBlockUnlocked(i)) n += TRACKS_PER_BLOCK;
        return n;
    }

    // How many "<grade> Medal" items we have received.
    int MedalCount(Medal g) const {
        int64 n = 0;
        m_itemCounts.Get(MedalItemName(g), n);
        return int(n);
    }

    // Vanilla always arms Bronze upward so bare/low finishes still count for the
    // milestone + goal tracking; item styles honour the user's floor.
    Medal EffectiveRequiredMedal() const {
        return VanillaMode() ? Medal::Bronze : S_RequiredMedal;
    }

    int ItemCount(const string &in name) const {
        int64 n = 0; m_itemCounts.Get(name, n); return int(n);
    }

    private string MedalItemName(Medal g) const {
        if (g == Medal::Bronze) return "Bronze Medal";
        if (g == Medal::Silver) return "Silver Medal";
        if (g == Medal::Gold)   return "Gold Medal";
        return "";
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
        RecomputeBlocks();
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
        // Everything else is counted (progressive series unlocks, medals, filler,
        // traps). Use the int64 Get/Set overloads explicitly -- the generic
        // dictionary ?&out path does not reliably round-trip a 32-bit int here.
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

    // Goal: read from slot_data. campaign_finish = crossed the line on all 200.
    void CheckGoal() {
        if (!S_AutoGoal || m_client is null || !m_client.IsReady || m_goalReported) return;
        auto loc = m_client.locations;
        bool done = false;
        if (m_goal == "campaign_finish") {
            done = loc.FinishedCountAll() >= 200;
        } else if (m_goal == "author_times") {
            done = false;   // reserved for a later "super solo" mode
        } else {
            done = loc.TotalCount > 0 && loc.CheckedCount >= loc.TotalCount;
        }
        if (done) {
            m_goalReported = true;
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
