# typed: true
# frozen_string_literal: true

require "test_helper"

class BulkSponsorshipTierSelectionTest < GitHub::TestCase
  context "validations" do
    test "requires a sponsor" do
      tier_selection = BulkSponsorshipTierSelection.new(sponsor_id: nil)
      refute_predicate tier_selection, :valid?
      assert_includes tier_selection.errors[:sponsor_id], "can't be blank"
    end

    test "requires some tier IDs" do
      tier_selection = BulkSponsorshipTierSelection.new(sponsors_tier_ids: [])
      refute_predicate tier_selection, :valid?
      assert_includes tier_selection.errors[:sponsors_tier_ids], "can't be blank"
    end

    test "requires tier IDs to be valid" do
      invalid_tier_id = SponsorsTier.maximum(:id).to_i + 1
      tier_selection = BulkSponsorshipTierSelection.new(sponsors_tier_ids: [invalid_tier_id])
      refute_predicate tier_selection, :valid?
      assert_includes tier_selection.errors[:sponsors_tier_ids], "contains invalid tier IDs: #{invalid_tier_id}"
    end

    test "requires a unique sponsor" do
      sponsor = create(:user)
      tier_selection1 = create(:bulk_sponsorship_tier_selection, sponsor: sponsor)

      tier_selection2 = BulkSponsorshipTierSelection.new(sponsor: sponsor)

      refute_predicate tier_selection2, :valid?
      assert_includes tier_selection2.errors[:sponsor_id], "has already been taken"
    end

    test "sorts and deduplicates tier IDs" do
      tier1, tier2 = create_pair(:sponsors_tier)
      assert_operator tier1.id, :<, tier2.id, "need tier1's ID to come before tier2's"
      tier_selection = BulkSponsorshipTierSelection.new(sponsors_tier_ids: [tier2.id, tier1.id, tier2.id])

      tier_selection.valid? # trigger normalization

      assert_equal [tier1.id, tier2.id], tier_selection.sponsors_tier_ids
    end
  end
end
