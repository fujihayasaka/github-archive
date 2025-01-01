# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::TwoFactorRecoveryCodesCheckTest < GitHub::TestCase
  fixtures do
    @user = create(:user, :verified)
  end

  context "#should_show_notice?" do
    test "returns true when user has two factor enabled and has not viewed recovery codes" do
      @user.two_factor_credential = create(:two_factor_credential)
      @user.save!

      assert_equal true, @user.two_factor_authentication_enabled?
      refute_predicate @user.two_factor_credential, :recovery_codes_viewed?

      check = GlobalNoticeNext::TwoFactorRecoveryCodesCheck.new(viewer: @user)

      assert check.should_show_notice?
    end

    test "returns false if user has two factor enabled and viewed codes" do
      @user.two_factor_credential = create(:two_factor_credential)
      @user.two_factor_credential.recovery_codes_viewed!
      @user.save!

      check = GlobalNoticeNext::TwoFactorRecoveryCodesCheck.new(viewer: @user.reload)

      refute check.should_show_notice?
    end

    test "returns false user does not have two factor" do
      check = GlobalNoticeNext::TwoFactorRecoveryCodesCheck.new(viewer: @user)

      refute check.should_show_notice?
    end
  end
end
