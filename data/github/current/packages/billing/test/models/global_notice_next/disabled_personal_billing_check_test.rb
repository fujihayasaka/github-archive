# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::DisabledPersonalBillingCheckTest < GitHub::TestCase
  fixtures do
    @user = create(:user, :verified, plan: "small")
  end

  context "#should_show_notice?" do
    test "returns true if a user is disabled" do
      @user.disabled = true
      @user.save

      check = GlobalNoticeNext::DisabledPersonalBillingCheck.new(viewer: @user)

      assert check.should_show_notice?
    end

    test "returns false if user is not disabled" do
      check = GlobalNoticeNext::DisabledPersonalBillingCheck.new(viewer: @user)

      refute check.should_show_notice?
    end
  end
end
