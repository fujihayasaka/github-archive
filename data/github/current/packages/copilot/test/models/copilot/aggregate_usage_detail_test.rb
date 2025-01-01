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

  context "create_for_user" do
    test "individual user creates" do
      user = create(:user)
      freeze_time do
        assert_changes -> { Copilot::AggregateUsageDetail.count }, from: 0, to: 1 do
          Copilot::AggregateUsageDetail.create_for_user(user, "1.0.0/1.0.0")
        end

        detail = T.must(Copilot::AggregateUsageDetail.last)

        sleep 1
        assert_no_changes -> { Copilot::AggregateUsageDetail.count } do
          Copilot::AggregateUsageDetail.create_for_user(user, "1.0.0/1.0.0")
        end

        other_detail = T.must(Copilot::AggregateUsageDetail.last)
        assert_equal other_detail.user_id, detail.user_id
        refute_equal other_detail.updated_at, detail.updated_at
      end
    end
  end
end if GitHub.copilot_enabled?
