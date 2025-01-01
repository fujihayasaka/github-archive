# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::DisabledOrgBillingCheckTest < GitHub::TestCase
  fixtures do
    @user = create(:user, :verified, plan: "small")
  end

  context "#should_show_notice?" do
    test "returns true if user owned org is disabled" do
      org = create :credit_card_organization, :with_billing_locked, admin: @user, billing_attempts: 7
      if GitHub.flipper[:use_billing_locked_rather_than_disabled].enabled?
        org.customer.lock_billing
      end

      check = GlobalNoticeNext::DisabledOrgBillingCheck.new(viewer: @user)

      assert check.should_show_notice?
    end

    test "returns false if user has no disabled orgs" do
      check = GlobalNoticeNext::DisabledOrgBillingCheck.new(viewer: @user)

      refute check.should_show_notice?
    end
  end
end
