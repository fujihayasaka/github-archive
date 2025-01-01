# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::AggregateUsageDetailTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "latest_for_users" do
    test "returns the latest usage detail for a user" do
      freeze_time do
        user = create(:user)
        create(:copilot_aggregate_usage_detail, user: user, usage_date: Date.today - 1.day)
        detail = create(:copilot_aggregate_usage_detail, user: user)
        assert_equal detail, Copilot::AggregateUsageDetail.latest_for_users(user)
      end
    end

    test "returns the latest usage detail for a number of users" do
      freeze_time do
        user = create(:user)
        other_user = create(:user)
        create(:copilot_aggregate_usage_detail, user: user, usage_date: Date.today - 1.day)
        detail = create(:copilot_aggregate_usage_detail, user: other_user)
        assert_equal detail, Copilot::AggregateUsageDetail.latest_for_users([user, other_user])
      end
    end
  end
end if GitHub.copilot_enabled?
