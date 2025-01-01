# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::Copilot::CodeReviewQuotaTest < GitHub::TestCase
  skip_enterprise

  context "#has_quota_remaining?" do
    test "returns true if remaining quota is more than 0" do
      assert PullRequests::Copilot::CodeReviewQuota.new(copilot_user: @copilot_user).has_quota_remaining?
    end

    test "returns false if remaining quota is 0" do
      crq = PullRequests::Copilot::CodeReviewQuota.new(copilot_user: @copilot_user)
      crq.stubs(:remaining_quota).returns(0.0)
      refute crq.has_quota_remaining?
    end
  end

  context "#remaining_quota" do
    test "returns a value between 0.0 and 1.0" do
      assert PullRequests::Copilot::CodeReviewQuota.new(copilot_user: @copilot_user).remaining_quota >= 0.0
      assert PullRequests::Copilot::CodeReviewQuota.new(copilot_user: @copilot_user).remaining_quota <= 1.0
    end
  end
end
