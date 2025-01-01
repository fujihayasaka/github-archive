# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::BusinessBillingTroubleCheckTest < GitHub::TestCase
  fixtures do
    @user = create(:user, :verified, plan: "small")
  end

  context "#should_show_notice?" do
    test "returns true if a user owned Business is having billing trouble" do
      business = create :business, owners: [@user]
      business.customer.update billing_attempts: 3

      check = GlobalNoticeNext::BusinessBillingTroubleCheck.new(viewer: @user)

      assert check.should_show_notice?
    end

    test "returns false if no user owned Business is having billing trouble" do
      check = GlobalNoticeNext::BusinessBillingTroubleCheck.new(viewer: @user)
      refute check.should_show_notice?
    end
  end
end if GitHub.billing_enabled?
