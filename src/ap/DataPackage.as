// Holds the server's data package for our game: the authoritative id <-> name
// maps for locations and items. Cached to disk so we skip GetDataPackage when
// the checksum is unchanged.

class DataPackage {
    dictionary m_locationNameToId;   // string -> int
    dictionary m_locationIdToName;   // string(int) -> string
    dictionary m_itemIdToName;       // string(int) -> string
    private string m_checksum;
    bool m_loaded = false;

    bool get_Loaded() const { return m_loaded; }
    string get_Checksum() const { return m_checksum; }

    void LoadFromServer(Json::Value@ gamePackage) {
        m_locationNameToId.DeleteAll();
        m_locationIdToName.DeleteAll();
        m_itemIdToName.DeleteAll();

        // Dictionary int values must go through the int64 Get/Set overloads --
        // the generic ?&out path does not round-trip a 32-bit int on this build.
        Json::Value@ locs = gamePackage["location_name_to_id"];
        array<string>@ locKeys = locs.GetKeys();
        for (uint i = 0; i < locKeys.Length; i++) {
            int idInt = locs[locKeys[i]];
            int64 id = idInt;
            m_locationNameToId.Set(locKeys[i], id);
            m_locationIdToName.Set(tostring(id), locKeys[i]);
        }

        Json::Value@ items = gamePackage["item_name_to_id"];
        array<string>@ itemKeys = items.GetKeys();
        for (uint i = 0; i < itemKeys.Length; i++) {
            int idInt = items[itemKeys[i]];
            m_itemIdToName.Set(tostring(int64(idInt)), itemKeys[i]);
        }

        if (gamePackage.HasKey("checksum")) m_checksum = gamePackage["checksum"];
        m_loaded = true;
        Persist();
        Log::Info("Data package loaded: " + locKeys.Length + " locations, " + itemKeys.Length + " items");
    }

    int LocationId(const string &in name) {
        int64 id = -1;
        return m_locationNameToId.Get(name, id) ? int(id) : -1;
    }

    string LocationName(int id) {
        string n;
        return m_locationIdToName.Get(tostring(id), n) ? n : ("Location#" + id);
    }

    string ItemName(int id) {
        string n;
        return m_itemIdToName.Get(tostring(id), n) ? n : ("Item#" + id);
    }

    // ---- persistence --------------------------------------------------
    // IO::FromStorageFolder resolves under the plugin's own data directory.
    private string CachePath() { return IO::FromStorageFolder("datapackage.json"); }

    private void Persist() {
        Json::Value@ root = Json::Object();
        root["checksum"] = m_checksum;
        root["locations"] = DictToJson(m_locationNameToId);
        root["items"] = IdNameDictToJson(m_itemIdToName);
        Json::ToFile(CachePath(), root);
    }

    void LoadCache() {
        if (!IO::FileExists(CachePath())) return;
        Json::Value@ root = Json::FromFile(CachePath());
        if (root is null) return;
        m_checksum = root["checksum"];
        // Full restore omitted for brevity of the skeleton -- the client
        // always re-fetches when the checksum mismatches anyway.
    }

    private Json::Value@ DictToJson(dictionary@ d) {
        Json::Value@ o = Json::Object();
        array<string>@ keys = d.GetKeys();
        for (uint i = 0; i < keys.Length; i++) { int64 v = 0; d.Get(keys[i], v); o[keys[i]] = v; }
        return o;
    }
    private Json::Value@ IdNameDictToJson(dictionary@ d) {
        Json::Value@ o = Json::Object();
        array<string>@ keys = d.GetKeys();
        for (uint i = 0; i < keys.Length; i++) { string v; d.Get(keys[i], v); o[keys[i]] = v; }
        return o;
    }
}
