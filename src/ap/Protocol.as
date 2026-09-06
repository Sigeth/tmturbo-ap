// Archipelago network protocol constants and (de)serialization helpers.
// Reference: https://github.com/ArchipelagoMW/Archipelago/blob/main/docs/network%20protocol.md
//
// The game name string MUST match the .apworld registered on the server side.
const string AP_GAME_NAME = "Trackmania Turbo";

// Client version advertised in the Connect packet. Bump the AP protocol part
// only when tested against that server release.
const int AP_VER_MAJOR = 0;
const int AP_VER_MINOR = 5;
const int AP_VER_BUILD = 1;

// items_handling bitflags in the Connect packet.
//   1 = receive items from other worlds
//   2 = receive items from your own world (starting inventory excluded)
//   4 = receive starting inventory
// 7 = everything; this is what a normal client wants.
const int AP_ITEMS_HANDLING_ALL = 7;

// ClientStatus enum (StatusUpdate packet).
namespace ClientStatus {
    const int Unknown    = 0;
    const int Connected  = 5;
    const int Ready      = 10;
    const int Playing    = 20;
    const int Goal       = 30;
}

namespace Packet {
    // ---- outbound -------------------------------------------------------

    string Connect(const string &in slotName, const string &in password, const string &in uuid) {
        Json::Value@ p = Json::Object();
        p["cmd"]  = "Connect";
        p["game"] = AP_GAME_NAME;
        p["name"] = slotName;
        p["password"] = password;
        p["uuid"] = uuid;
        p["version"] = Version();
        p["items_handling"] = AP_ITEMS_HANDLING_ALL;
        p["tags"] = Json::Array();
        p["slot_data"] = true;
        return WrapArray(p);
    }

    string Sync() {
        Json::Value@ p = Json::Object();
        p["cmd"] = "Sync";
        return WrapArray(p);
    }

    string LocationChecks(const array<int> &in locationIds) {
        Json::Value@ p = Json::Object();
        p["cmd"] = "LocationChecks";
        Json::Value@ arr = Json::Array();
        for (uint i = 0; i < locationIds.Length; i++) arr.Add(Json::Value(locationIds[i]));
        p["locations"] = arr;
        return WrapArray(p);
    }

    string StatusUpdate(int status) {
        Json::Value@ p = Json::Object();
        p["cmd"] = "StatusUpdate";
        p["status"] = status;
        return WrapArray(p);
    }

    string GetDataPackage(const array<string> &in games) {
        Json::Value@ p = Json::Object();
        p["cmd"] = "GetDataPackage";
        Json::Value@ arr = Json::Array();
        for (uint i = 0; i < games.Length; i++) arr.Add(Json::Value(games[i]));
        p["games"] = arr;
        return WrapArray(p);
    }

    // ---- helpers -------------------------------------------------------

    Json::Value@ Version() {
        Json::Value@ v = Json::Object();
        v["major"] = AP_VER_MAJOR;
        v["minor"] = AP_VER_MINOR;
        v["build"] = AP_VER_BUILD;
        v["class"] = "Version";
        return v;
    }

    // Archipelago always frames packets as a JSON array of command objects.
    string WrapArray(Json::Value@ obj) {
        Json::Value@ arr = Json::Array();
        arr.Add(obj);
        return Json::Write(arr);
    }

    // Parse an inbound frame (a JSON array) into individual command objects.
    array<Json::Value@>@ Parse(const string &in frame) {
        array<Json::Value@> cmds;
        Json::Value@ arr = Json::Parse(frame);
        if (arr is null || arr.GetType() != Json::Type::Array) {
            Log::Warn("dropped malformed frame");
            return cmds;
        }
        for (uint i = 0; i < arr.Length; i++) cmds.InsertLast(arr[i]);
        return cmds;
    }
}
