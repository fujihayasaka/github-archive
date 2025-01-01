# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::BillingEmailCheckTest < GitHub::TestCase
  fixtures do
    @user = create(:user, :verified, plan: "small")
  end

  context "#should_show_notice?" do
    test "returns true if user is having billing trouble" do
      @user.emails.first.update_column :email, "not valid"
      @user.reload
      assert @user.billing_email_invalid?

      check = GlobalNoticeNext::BillingEmailCheck.new(viewer: @user)

      assert check.should_show_notice?
    end

    test "returns false if user is not having billing trouble" do
      check = GlobalNoticeNext::BillingEmailCheck.new(viewer: @user)

      refute check.should_show_notice?
    end
  end
end
