# typed: false
# frozen_string_literal: true

require "test_helper"

class ContributionRestrictedContributionTest < GitHub::TestCase
  test "delegates methods to contribution" do
    user = create(:user)
    contribution = Contribution.new(user: user)
    restricted_contribution = Contribution::RestrictedContribution.new(contribution)
    assert_equal user, restricted_contribution.user
  end

  test "doesn't delegate methods with private information" do
    user = create(:user)
    contribution = Contribution.new(user: user)
    restricted_contribution = Contribution::RestrictedContribution.new(contribution)

    assert_raises(NoMethodError) do
      restricted_contribution.subject
    end
  end
end
