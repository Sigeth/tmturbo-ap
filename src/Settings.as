// All user-configurable options. Openplanet persists these automatically to
// OpenplanetTurbo/Plugins/Archipelago/... via the [Setting] metadata.

[Setting category="Connection" name="Server host"]
string S_Host = "archipelago.gg";

[Setting category="Connection" name="Server port" min=1 max=65535]
int S_Port = 38281;

[Setting category="Connection" name="Use TLS (wss://)"]
bool S_UseTls = true;

[Setting category="Connection" name="Slot name"]
string S_SlotName = "";

[Setting category="Connection" name="Password" password]
string S_Password = "";

[Setting category="Connection" name="Auto-connect on plugin load"]
bool S_AutoConnect = false;

[Setting category="Behaviour" name="Medal required to check a track location"]
Medal S_RequiredMedal = Medal::Gold;

[Setting category="Behaviour" name="Report goal complete automatically"]
bool S_AutoGoal = true;

[Setting category="Debug" name="Verbose protocol logging"]
bool S_Trace = false;

// The medal tiers Turbo exposes per official-campaign track.
enum Medal {
    Bronze = 1,
    Silver = 2,
    Gold   = 3,
    Author = 4,
}

string ServerUrl() {
    string scheme = S_UseTls ? "wss" : "ws";
    return scheme + "://" + S_Host + ":" + tostring(S_Port);
}
