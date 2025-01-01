# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestsCopilotTest < GitHub::TestCase
  include CopilotTestHelper
  include CopilotPublicUserCacheable

  fixtures do
    copilot_seat = create(:copilot_seat, :organization)
    @repository = create(:repository)
    @org = copilot_seat.organization
    @user = copilot_seat.assigned_user
  end

  context ".copilot_for_prs_enabled?" do
    test "returns true if the policy is enabled" do
      Copilot::Organization.new(@org).copilot_for_dotcom_enabled!

      assert_predicate Copilot::User.new(@user), :pr_summarizations_enabled?
      assert PullRequests::Copilot.copilot_for_prs_enabled?(::Copilot::Public::User.new(@user))
    end

    test "returns false if the policy is disabled" do
      refute_predicate Copilot::User.new(@user), :pr_summarizations_enabled?
      refute PullRequests::Copilot.copilot_for_prs_enabled?(::Copilot::Public::User.new(@user))
    end
  end
end
