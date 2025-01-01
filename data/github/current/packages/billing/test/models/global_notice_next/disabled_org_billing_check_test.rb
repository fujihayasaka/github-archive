# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::DisabledOrgBillingCheckTest < GitHub::TestCase
  fixtures do
    @user = create(:user, :verified, plan: "small")
  end

  context "#should_show_notice?" do
    test "returns true if user owned org is disabled" do
      create :organization, admin: @user, disabled: true, billing_attempts: 7

      check = GlobalNoticeNext::DisabledOrgBillingCheck.new(viewer: @user)

      assert check.should_show_notice?
    end

    test "returns false if user has no disabled orgs" do
      check = GlobalNoticeNext::DisabledOrgBillingCheck.new(viewer: @user)

      refute check.should_show_notice?
    end
  end
end
