# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsIssueSubscriptionTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user    = create(:user)
    @mention = Stafftools::IssueSubscription.new(@user, "mention")
  end

  context "#user" do
    test "returns the user" do
      assert_equal @user, @mention.user
    end
  end

  context "#reason" do
    test "returns the reason" do
      assert_equal "mention", @mention.reason
    end
  end
end
