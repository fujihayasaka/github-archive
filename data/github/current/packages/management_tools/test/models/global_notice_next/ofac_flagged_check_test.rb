# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::OFACFlaggedCheckTest < GitHub::TestCase
  context "#should_show_notice?" do
    test "returns true when user is trade restricted" do
      user = create(:user, :fully_trade_restricted, :verified)
      user.reset_notice Billing::OFACCompliance::USER_NOTICE_FLAG

      check = GlobalNoticeNext::OFACFlaggedCheck.new(viewer: user)

      assert check.should_show_notice?
    end

    test "returns false when notice is dismissed" do
      user = create(:user, :fully_trade_restricted, :verified)
      user.reset_notice Billing::OFACCompliance::USER_NOTICE_FLAG
      user.dismiss_notice Billing::OFACCompliance::USER_NOTICE_FLAG

      check = GlobalNoticeNext::OFACFlaggedCheck.new(viewer: user)

      refute check.should_show_notice?
    end

    test "returns false when user is not trade restricted" do
      user = create(:user)
      check = GlobalNoticeNext::OFACFlaggedCheck.new(viewer: user)

      refute check.should_show_notice?
    end
  end
end
