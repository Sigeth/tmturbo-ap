// Maps a Turbo official-campaign map to its AP location base name.
//
// There is no UID table. The Turbo solo campaign is 200 maps authored by
// "Nadeo" and named "001".."200"; that number alone identifies the track. This
// is how the Ultimate Medals plugin detects campaign maps
// (Text::ParseInt(challenge.MapName) + AuthorLogin == "Nadeo") -- see
// Phlarx/tm-ultimate-medals, UltimateMedals.as.
//
// Campaign layout (difficulty-major, then environment, then 1..10):
//   tier = (n-1) / 40   ->  White Green Blue Red Black
//   env  = (n-1) % 40 / 10  ->  Canyon Valley Lagoon Stadium
//   idx  = (n-1) % 10 + 1   ->  1..10
// so map 001 = "White Canyon 01", map 200 = "Black Stadium 10".
//
// Environment order within a tier (Canyon -> Valley -> Lagoon -> Stadium) matches
// the in-game unlock progression. VERIFY against the GameState trace log
// ("campaign map N -> <label>") when loading real tracks.
//
// AP location name convention (must match the .apworld):
//   "<Track Label> - <Medal>"   e.g. "White Canyon 01 - Gold"

const string CAMPAIGN_AUTHOR_LOGIN = "Nadeo";
const array<string> TIERS = { "White", "Green", "Blue", "Red", "Black" };
const array<string> ENVIRONMENTS = { "Canyon", "Valley", "Lagoon", "Stadium" };
const int TRACKS_PER_TIER = 40;
const int TRACKS_PER_ENV = 10;
const array<string> MEDAL_SUFFIX = { "", "Bronze", "Silver", "Gold", "Author" };

// "001".."200" from a Nadeo-authored map -> 1..200; anything else -> 0.
int CampaignNumber(const string &in mapName, const string &in authorLogin) {
    if (authorLogin != CAMPAIGN_AUTHOR_LOGIN) return 0;
    int n = 0;
    if (!Text::TryParseInt(mapName, n)) return 0;
    return (n >= 1 && n <= 200) ? n : 0;
}

// 1..200 -> "White Canyon 01"; 0 or out of range -> "".
string TrackLabel(int campaignNumber) {
    if (campaignNumber < 1 || campaignNumber > 200) return "";
    int z = campaignNumber - 1;
    string tier = TIERS[z / TRACKS_PER_TIER];
    string env = ENVIRONMENTS[(z % TRACKS_PER_TIER) / TRACKS_PER_ENV];
    int idx = z % TRACKS_PER_ENV + 1;
    return tier + " " + env + " " + (idx < 10 ? "0" : "") + idx;
}

// The nth track (1..40) of a tier, in campaign order -- for progressive unlocks.
string TierTrackLabel(const string &in tier, int nth) {
    int tierIdx = TIERS.Find(tier);
    if (tierIdx < 0 || nth < 1 || nth > TRACKS_PER_TIER) return "";
    return TrackLabel(tierIdx * TRACKS_PER_TIER + nth);
}

string TrackLocationName(const string &in trackLabel, Medal medal) {
    if (trackLabel == "" || int(medal) < 1 || int(medal) > 4) return "";
    return trackLabel + " - " + MEDAL_SUFFIX[int(medal)];
}
