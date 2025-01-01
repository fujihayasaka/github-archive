# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::PersonalBillingTroubleCheckTest < GitHub::TestCase
  fixtures do
    @user = create(:user, :verified, plan: "small")
  end

  context "#should_show_notice?" do
    test "returns true if user is having billing trouble" do
      @user.billed_on = Date.today + 2.days
      @user.billing_attempts = 3
      @user.save!
      assert @user.billing_trouble?

      check = GlobalNoticeNext::PersonalBillingTroubleCheck.new(viewer: @user)

      assert check.should_show_notice?
    end

    test "returns false if user is not having billing trouble" do
      refute @user.billing_trouble?

      check = GlobalNoticeNext::PersonalBillingTroubleCheck.new(viewer: @user)

      refute check.should_show_notice?
    end
  end
end
