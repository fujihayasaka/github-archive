# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionContributionsByStateTest < GitHub::TestCase
  context "#total_contributions" do
    test "returns a count of given contributions" do
      contribs_by_state = Contribution::ContributionsByState.new(
        contributions: [stub, stub], repository: stub, state: "open",
        contribution_type: Contribution::CreatedIssue
      )
      assert_equal 2, contribs_by_state.total_contributions
    end
  end
end
