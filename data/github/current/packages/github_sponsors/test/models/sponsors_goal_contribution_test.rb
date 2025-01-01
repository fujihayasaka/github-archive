# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsGoalContributionTest < GitHub::TestCase
  if GitHub.sponsors_enabled?
    fixtures do
      @goal_contribution = create(:sponsors_goal_contribution)
    end

    context "validations" do
      test "requires a sponsors goal" do
        @goal_contribution.goal = nil

        refute_predicate @goal_contribution, :valid?
        assert_includes @goal_contribution.errors[:goal], "must exist"
      end

      test "requires a sponsors tier" do
        @goal_contribution.tier = nil

        refute_predicate @goal_contribution, :valid?
        assert_includes @goal_contribution.errors[:tier], "must exist"
      end

      test "requires a sponsor" do
        @goal_contribution.sponsor = nil

        refute_predicate @goal_contribution, :valid?
        assert_includes @goal_contribution.errors[:sponsor], "must exist"
      end
    end
  end
end
