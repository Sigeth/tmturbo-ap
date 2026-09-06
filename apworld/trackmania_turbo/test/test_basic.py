from . import TrackmaniaTurboTestBase


class TestVanillaDefault(TrackmaniaTurboTestBase):
    """Default YAML -> unlock_style: vanilla."""

    def test_id_map_universe(self):
        # The id map is the stable universe: 200 tracks x 4 medal tiers + 20
        # block milestones + 5 tier milestones; items are 5 Progressive + filler
        # + 3 medal items.
        self.assertEqual(len(self.world.location_name_to_id), 200 * 4 + 20 + 5)
        self.assertEqual(len(self.world.item_name_to_id), 5 + 1 + 3)

    def test_instantiated_location_count(self):
        # Gold + Author per track, plus the 25 milestones.
        locs = [loc for loc in self.multiworld.get_locations(1)]
        self.assertEqual(len(locs), 200 * 2 + 25)

    def test_no_track_unlock_items_in_pool(self):
        for item in self.multiworld.itempool:
            self.assertFalse(item.name.startswith("Progressive "))
            self.assertFalse(item.name.startswith("Unlock: "))

    def test_medal_items_are_progression(self):
        medals = [i for i in self.multiworld.itempool if i.name.endswith(" Medal")]
        self.assertTrue(medals)
        self.assertTrue(all(i.advancement for i in medals))

    def test_first_track_reachable_from_start(self):
        loc = self.multiworld.get_location("White Canyon 01 - Gold", 1)
        self.assertTrue(loc.can_reach(self.multiworld.state))

    def test_milestones_exist(self):
        self.multiworld.get_location("White Canyon Complete", 1)
        self.multiworld.get_location("Black Complete", 1)

    def test_completion_needs_full_medal_counts(self):
        self.collect_by_name(["Bronze Medal"] * 70)
        self.collect_by_name(["Silver Medal"] * 150)
        self.assertBeatable(False)
        self.collect_by_name(["Gold Medal"] * 190)
        self.assertBeatable(True)


class TestVanillaMedalsRequiredIgnored(TrackmaniaTurboTestBase):
    options = {"unlock_style": "vanilla", "medals_required": "gold"}

    def test_still_gold_and_author(self):
        loc_names = {loc.name for loc in self.multiworld.get_locations(1)}
        self.assertIn("White Canyon 01 - Gold", loc_names)
        self.assertIn("White Canyon 01 - Author", loc_names)
        self.assertNotIn("White Canyon 01 - Bronze", loc_names)


class TestProgressive(TrackmaniaTurboTestBase):
    options = {"unlock_style": "progressive"}

    def test_location_count(self):
        locs = [loc for loc in self.multiworld.get_locations(1)]
        self.assertEqual(len(locs), 200 * 2)  # Gold + Author, no milestones

    def test_progressive_pool(self):
        prog = [i for i in self.multiworld.itempool if i.name.startswith("Progressive ")]
        self.assertEqual(len(prog), (40 - 1) * 5)  # 39 per tier in the pool

    def test_goal_needs_all_tiers(self):
        self.collect_all_but(["Progressive Black"])
        self.assertBeatable(False)
        self.collect_by_name("Progressive Black")
        self.assertBeatable(True)


class TestIndividualRejected(TrackmaniaTurboTestBase):
    options = {"unlock_style": "individual"}
    auto_construct = False

    def test_individual_raises(self):
        from Options import OptionError
        self.assertRaises(OptionError, self.world_setup)
