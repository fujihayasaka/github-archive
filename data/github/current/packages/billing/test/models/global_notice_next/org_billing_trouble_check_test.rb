# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::OrgBillingTroubleCheckTest < GitHub::TestCase
  fixtures do
    @user = create(:user, :verified, plan: "small")
  end

  context "#should_show_notice?" do
    test "returns true if a user owned org is having billing trouble" do
      create :organization, admin: @user, billing_attempts: 3

      check = GlobalNoticeNext::OrgBillingTroubleCheck.new(viewer: @user)

      assert check.should_show_notice?
    end

    test "returns false if no user owned org is having billing trouble" do
      check = GlobalNoticeNext::OrgBillingTroubleCheck.new(viewer: @user)

      refute check.should_show_notice?
    end
  end
end
