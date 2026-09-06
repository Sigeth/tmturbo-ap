// The Archipelago session state machine.
//
// Owns the Transport, performs the handshake, dispatches inbound commands to the
// LocationManager / ItemManager, and exposes a small imperative surface
// (Connect / Disconnect / CheckLocations / ReportGoal) to the rest of the plugin.
//
// Drive it by calling Update() once per frame (Main.as does this from a coroutine).

namespace Ap {
    enum Phase {
        Disconnected,   // no socket
        Socket,         // socket opening
        RoomInfo,       // waiting for RoomInfo
        DataPackage,    // GetDataPackage sent, waiting
        Authenticating, // Connect sent, waiting for Connected / ConnectionRefused
        Ready,          // fully connected and synced
        Error,          // terminal; see LastError
    }
}

class ApClient {
    Transport@ transport = Transport();
    DataPackage@ data = DataPackage();
    LocationManager@ locations;
    ItemManager@ items;

    private Ap::Phase m_phase = Ap::Phase::Disconnected;
    private string m_lastError;
    private string m_uuid;
    private int m_slotNr = -1;
    private Json::Value@ m_slotData;

    // room metadata surfaced to the UI
    string seedName;
    array<string> playerNames;

    Ap::Phase get_Phase() const { return m_phase; }
    string get_LastError() const { return m_lastError; }
    bool get_IsReady() const { return m_phase == Ap::Phase::Ready; }
    Json::Value@ get_SlotData() { return m_slotData; }
    int get_SlotNr() const { return m_slotNr; }

    ApClient() {
        @locations = LocationManager(this);
        @items = ItemManager(this);
        m_uuid = PersistentUuid();
    }

    // ---- public control ------------------------------------------------

    void Connect() {
        if (S_SlotName == "") { SetError("set a slot name in the settings first"); return; }
        m_lastError = "";
        @m_slotData = null;
        m_slotNr = -1;
        locations.Reset();
        items.Reset();
        transport.Connect(ServerUrl());
        m_phase = Ap::Phase::Socket;
    }

    void Disconnect() {
        transport.Close();
        m_phase = Ap::Phase::Disconnected;
    }

    // Called by LocationManager once it has resolved game events to ids.
    void SendLocationChecks(const array<int> &in ids) {
        if (!IsReady || ids.Length == 0) return;
        transport.Send(Packet::LocationChecks(ids));
    }

    void ReportGoal() {
        if (!IsReady) return;
        transport.Send(Packet::StatusUpdate(ClientStatus::Goal));
        Log::Info("Goal reported to Archipelago");
    }

    // ---- frame tick --------------------------------------------------

    void Update() {
        array<string>@ frames = transport.Pump();

        // Escalate transport failures into a client error.
        if (transport.State == Transport::State::Failed && m_phase != Ap::Phase::Error) {
            SetError(transport.LastError);
            return;
        }
        if (m_phase == Ap::Phase::Socket && transport.IsOpen) {
            m_phase = Ap::Phase::RoomInfo;
        }

        for (uint i = 0; i < frames.Length; i++) {
            array<Json::Value@>@ cmds = Packet::Parse(frames[i]);
            for (uint c = 0; c < cmds.Length; c++) Dispatch(cmds[c]);
        }
    }

    // ---- inbound dispatch -------------------------------------------

    private void Dispatch(Json::Value@ cmd) {
        string name = cmd["cmd"];
        if      (name == "RoomInfo")          OnRoomInfo(cmd);
        else if (name == "DataPackage")       OnDataPackage(cmd);
        else if (name == "Connected")         OnConnected(cmd);
        else if (name == "ConnectionRefused") OnConnectionRefused(cmd);
        else if (name == "ReceivedItems")     items.OnReceivedItems(cmd);
        else if (name == "RoomUpdate")        OnRoomUpdate(cmd);
        else if (name == "PrintJSON")         OnPrintJson(cmd);
        else if (name == "Bounced")           {}
        else if (name == "InvalidPacket")     Log::Warn("server rejected a packet: " + Json::Write(cmd));
        else Log::Trace("unhandled cmd: " + name);
    }

    private void OnRoomInfo(Json::Value@ cmd) {
        if (cmd.HasKey("seed_name")) seedName = cmd["seed_name"];

        // Decide whether the cached data package is still good.
        string serverChecksum;
        Json::Value@ sums = cmd["datapackage_checksums"];
        if (sums !is null && sums.HasKey(AP_GAME_NAME)) serverChecksum = sums[AP_GAME_NAME];

        if (data.Loaded && data.Checksum == serverChecksum && serverChecksum != "") {
            SendConnect();
        } else {
            array<string> games = { AP_GAME_NAME };
            transport.Send(Packet::GetDataPackage(games));
            m_phase = Ap::Phase::DataPackage;
        }
    }

    private void OnDataPackage(Json::Value@ cmd) {
        Json::Value@ games = cmd["data"]["games"];
        if (games.HasKey(AP_GAME_NAME)) {
            data.LoadFromServer(games[AP_GAME_NAME]);
        } else {
            SetError("server data package has no entry for '" + AP_GAME_NAME + "'");
            return;
        }
        SendConnect();
    }

    private void SendConnect() {
        transport.Send(Packet::Connect(S_SlotName, S_Password, m_uuid));
        m_phase = Ap::Phase::Authenticating;
    }

    private void OnConnected(Json::Value@ cmd) {
        m_slotNr = cmd["slot"];
        @m_slotData = cmd.HasKey("slot_data") ? cmd["slot_data"] : Json::Object();

        playerNames.Resize(0);
        Json::Value@ players = cmd["players"];
        for (uint i = 0; i < players.Length; i++) playerNames.InsertLast(string(players[i]["alias"]));

        // Seed the location manager with what the server already recorded.
        locations.SeedFromServer(cmd["checked_locations"], cmd["missing_locations"]);

        m_phase = Ap::Phase::Ready;
        Log::Info("Connected as slot " + m_slotNr + " (" + S_SlotName + ")");

        // Ask for the full item stream so re-connects replay unlocks.
        transport.Send(Packet::Sync());
        transport.Send(Packet::StatusUpdate(ClientStatus::Playing));
    }

    private void OnConnectionRefused(Json::Value@ cmd) {
        string reasons;
        Json::Value@ errs = cmd["errors"];
        for (uint i = 0; i < errs.Length; i++) reasons += (i > 0 ? ", " : "") + string(errs[i]);
        SetError("connection refused: " + reasons);
    }

    private void OnRoomUpdate(Json::Value@ cmd) {
        // Interesting fields: checked_locations (others' progress in co-op),
        // hint_points, players. Forward location deltas so the UI stays live.
        if (cmd.HasKey("checked_locations")) locations.MarkChecked(cmd["checked_locations"]);
    }

    private void OnPrintJson(Json::Value@ cmd) {
        // Server chat / item routing feed. Render only the plain text parts.
        string line;
        Json::Value@ parts = cmd["data"];
        for (uint i = 0; i < parts.Length; i++) line += string(parts[i]["text"]);
        Log::Info(line);
    }

    private void SetError(const string &in why) {
        m_lastError = why;
        m_phase = Ap::Phase::Error;
        Log::Error(why);
        transport.Close();
    }

    // A stable per-install id so the server can dedupe reconnects.
    private string PersistentUuid() {
        string path = IO::FromStorageFolder("uuid.txt");
        if (IO::FileExists(path)) {
            IO::File f(path, IO::FileMode::Read);
            string v = f.ReadToEnd().Trim();
            f.Close();
            if (v != "") return v;
        }
        string v = "" + Math::Rand(0, 0x7fffffff) + "-" + Time::Stamp;
        IO::File f(path, IO::FileMode::Write);
        f.Write(v);
        f.Close();
        return v;
    }
}
