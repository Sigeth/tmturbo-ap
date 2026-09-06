// Turns game achievements into Archipelago location checks.
//
// A "location" in this apworld is one (track, medal-tier) pair. The mapping
// between a Turbo map UID and its AP location name lives in TrackTable.as; this
// class resolves those names to ids via the server data package and tracks which
// checks have already been sent so we never double-report.

class LocationManager {
    private ApClient@ m_client;

    private array<int> m_checked;        // location ids confirmed by the server
    private array<int> m_missing;        // location ids still in play this seed
    private array<int> m_pendingSend;    // resolved, not yet acknowledged

    LocationManager(ApClient@ client) { @m_client = client; }

    void Reset() {
        m_checked.Resize(0);
        m_missing.Resize(0);
        m_pendingSend.Resize(0);
    }

    int get_CheckedCount() const { return m_checked.Length; }
    int get_TotalCount() const { return m_checked.Length + m_missing.Length; }

    // Which medal tiers of a track have been checked, as a bitmask: bit t is set
    // (t = Medal enum, Bronze=1 .. Author=4) when that track/medal location id is
    // in m_checked. Used by the campaign overlay. Cheap: 4 dictionary lookups.
    int CheckedMedalMask(const string &in trackLabel) {
        int mask = 0;
        for (int t = int(Medal::Bronze); t <= int(Medal::Author); t++) {
            int id = m_client.data.LocationId(TrackLocationName(trackLabel, Medal(t)));
            if (id >= 0 && IsChecked(id)) mask |= (1 << t);
        }
        return mask;
    }

    // Which medal tiers of a track exist as AP locations at all (some seeds only
    // define Gold + Author). Bit t = Medal enum. The overlay hides the rest.
    int AvailableMedalMask(const string &in trackLabel) {
        int mask = 0;
        for (int t = int(Medal::Bronze); t <= int(Medal::Author); t++) {
            if (m_client.data.LocationId(TrackLocationName(trackLabel, Medal(t))) >= 0)
                mask |= (1 << t);
        }
        return mask;
    }

    // From the Connected packet.
    void SeedFromServer(Json::Value@ checked, Json::Value@ missing) {
        m_checked.Resize(0);
        for (uint i = 0; i < checked.Length; i++) m_checked.InsertLast(int(checked[i]));
        m_missing.Resize(0);
        for (uint i = 0; i < missing.Length; i++) m_missing.InsertLast(int(missing[i]));
        Log::Info("Locations: " + m_checked.Length + " checked / " + get_TotalCount() + " total");
    }

    // From RoomUpdate: ids other clients (or we) completed.
    void MarkChecked(Json::Value@ ids) {
        for (uint i = 0; i < ids.Length; i++) AddChecked(int(ids[i]));
    }

    // Called by Main.as when GameState reports a finish.
    void OnFinish(FinishEvent@ ev) {
        Log::Trace("OnFinish " + ev.trackLabel + " medal=" + int(ev.medal)
                   + " (S_RequiredMedal=" + int(S_RequiredMedal) + ")");
        // Every medal tier at or below the achieved one becomes checkable, but
        // gate on the user's configured minimum (S_RequiredMedal).
        for (int tier = int(S_RequiredMedal); tier <= int(ev.medal); tier++) {
            string locName = TrackLocationName(ev.trackLabel, Medal(tier));
            if (locName == "") continue;
            int id = m_client.data.LocationId(locName);
            Log::Trace("  tier " + tier + " '" + locName + "' -> id " + id);
            if (id < 0) { Log::Trace("no server id for '" + locName + "'"); continue; }
            if (IsChecked(id) || IsPending(id)) continue;
            m_pendingSend.InsertLast(id);
            Log::Info("Location armed: " + locName);
        }
        Flush();
    }

    // Push everything resolved-but-unsent to the server.
    void Flush() {
        if (m_pendingSend.Length == 0 || !m_client.IsReady) return;
        m_client.SendLocationChecks(m_pendingSend);
        // Optimistically mark as checked; RoomUpdate will confirm.
        for (uint i = 0; i < m_pendingSend.Length; i++) AddChecked(m_pendingSend[i]);
        m_pendingSend.Resize(0);
    }

    private void AddChecked(int id) {
        if (IsChecked(id)) return;
        m_checked.InsertLast(id);
        int idx = m_missing.Find(id);
        if (idx >= 0) m_missing.RemoveAt(idx);
    }
    private bool IsChecked(int id) const { return m_checked.Find(id) >= 0; }
    private bool IsPending(int id) const { return m_pendingSend.Find(id) >= 0; }
}
