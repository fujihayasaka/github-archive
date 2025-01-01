# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsEmailOptOutsTest < GitHub::TestCase
  context "#initialize" do
    test "returns email preferences object with default value" do
      result = SponsorsEmailOptOuts.new(bitmask: nil)
      assert_equal 0, result.bitmask
    end

    test "returns email preferences object with given value" do
      result = SponsorsEmailOptOuts.new(bitmask: 256)
      assert_equal 256, result.bitmask
    end
  end

  context "boolean methods" do
    SponsorsEmailOptOuts::BITMASK_POSITIONS.each do |key, value|
      method_name = "opted_out_of_#{key}?"

      test "#{method_name} returns false for default bitmask" do
        refute_predicate SponsorsEmailOptOuts.new(bitmask: nil), method_name.to_sym
      end

      test "#{method_name} returns true when bit is enabled" do
        bitmask = 1 << value
        assert_predicate SponsorsEmailOptOuts.new(bitmask: bitmask), method_name.to_sym
      end

      test "#{method_name} returns false when bit is not enabled" do
        bitmask = 1 << value + 1
        refute_predicate SponsorsEmailOptOuts.new(bitmask: bitmask), method_name.to_sym
      end

      test "#{method_name} returns true when multiple bits are enabled" do
        bitmask = 1 << value
        bitmask = bitmask | 1 << (value + 1)
        assert_predicate SponsorsEmailOptOuts.new(bitmask: bitmask), method_name.to_sym
      end
    end
  end

  context "#opt_out_of" do
    test "returns bitmask with bit enabled" do
      prefs = SponsorsEmailOptOuts.new(bitmask: nil)
      refute_predicate prefs, :opted_out_of_cancelled_sponsorships?

      prefs.opt_out_of(:cancelled_sponsorships)

      assert_predicate prefs, :opted_out_of_cancelled_sponsorships?
    end

    test "returns bitmask with bit enabled when already enabled" do
      opt_out_bitmask = 1 << T.must(SponsorsEmailOptOuts::BITMASK_POSITIONS[:cancelled_sponsorships])
      prefs = SponsorsEmailOptOuts.new(bitmask: opt_out_bitmask)
      assert_predicate prefs, :opted_out_of_cancelled_sponsorships?

      prefs.opt_out_of(:cancelled_sponsorships)

      assert_predicate prefs, :opted_out_of_cancelled_sponsorships?
    end

    test "does not affect other bits" do
      prefs = SponsorsEmailOptOuts.new(bitmask: nil)
      refute_predicate prefs, :opted_out_of_cancelled_sponsorships?
      refute_predicate prefs, :opted_out_of_new_sponsorships?

      prefs.opt_out_of(:cancelled_sponsorships)

      assert_predicate prefs, :opted_out_of_cancelled_sponsorships?
      refute_predicate prefs, :opted_out_of_new_sponsorships?
    end
  end

  context "#opt_in_to" do
    test "returns bitmask with bit disabled" do
      bitmask = 1 << T.must(SponsorsEmailOptOuts::BITMASK_POSITIONS[:goal_completed])
      prefs = SponsorsEmailOptOuts.new(bitmask: bitmask)

      assert_predicate prefs, :opted_out_of_goal_completed?

      prefs.remove_opt_out(:goal_completed)

      refute_predicate prefs, :opted_out_of_goal_completed?
    end

    test "returns bitmask with bit disabled when already disabled" do
      prefs = SponsorsEmailOptOuts.new(bitmask: nil)
      refute_predicate prefs, :opted_out_of_cancelled_sponsorships?

      prefs.remove_opt_out(:cancelled_sponsorships)

      refute_predicate prefs, :opted_out_of_cancelled_sponsorships?
    end

    test "does not affect other bits" do
      all_bits_enabled_bitmask = ~0
      prefs = SponsorsEmailOptOuts.new(bitmask: all_bits_enabled_bitmask)
      assert_predicate prefs, :opted_out_of_new_sponsorships?
      assert_predicate prefs, :opted_out_of_cancelled_sponsorships?
      assert_predicate prefs, :opted_out_of_upgrade_notices?
      assert_predicate prefs, :opted_out_of_goal_completed?
      assert_predicate prefs, :opted_out_of_milestone_reached?

      prefs.remove_opt_out(:upgrade_notices)

      refute_predicate prefs, :opted_out_of_upgrade_notices?

      assert_predicate prefs, :opted_out_of_new_sponsorships?
      assert_predicate prefs, :opted_out_of_cancelled_sponsorships?
      assert_predicate prefs, :opted_out_of_goal_completed?
      assert_predicate prefs, :opted_out_of_milestone_reached?
    end
  end
end
