"""YAML options for the Trackmania Turbo world."""

from dataclasses import dataclass

from Options import Choice, PerGameCommonOptions


class UnlockStyle(Choice):
    """How campaign tracks unlock.

    vanilla: mirrors Turbo's own campaign gating. The 200 tracks are 20 blocks of
      10 (5 tiers x 4 environments). Block i opens once you have received 10*i
      "medal" items of the block's grade -- Bronze for the White/Green blocks,
      Silver for Blue/Red, Gold for Black. Your pool has no track-unlock items;
      the medal items are the randomised progression.

    progressive: receive "Progressive <Tier>" items; the Nth unlocks that tier's
      Nth track in campaign order.

    individual: one "Unlock: <Track>" item per track (not implemented yet).
    """
    display_name = "Unlock Style"
    option_vanilla = 0
    option_progressive = 1
    option_individual = 2
    default = 0


class Goal(Choice):
    """Win condition (enforced by the plugin, read from slot_data).

    campaign_finish: cross the finish line -- any medal or none -- on all 200
      tracks.

    author_times: Author medal on all 200 tracks (reserved for a later "super
      solo" mode; not fully wired yet).
    """
    display_name = "Goal"
    option_campaign_finish = 0
    option_author_times = 1
    default = 0


class MedalsRequired(Choice):
    """Lowest medal tier that sends a location check. Only consulted by the
    progressive / individual unlock styles -- vanilla always uses Gold + Author.
    """
    display_name = "Medals Required"
    option_bronze = 0
    option_silver = 1
    option_gold = 2
    option_author = 3
    default = 2


@dataclass
class TrackmaniaTurboOptions(PerGameCommonOptions):
    unlock_style: UnlockStyle
    goal: Goal
    medals_required: MedalsRequired
