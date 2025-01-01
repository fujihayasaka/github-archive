# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::SponsorshipRollbackCheckTest < GitHub::TestCase
  fixtures do
    @user = create(:user, :verified, plan: "small")
  end

  context "#should_show_notice?" do
    test "returns true if user has a sponsorship rollback" do
      @user.set_sponsorship_rollback_notification
      check = GlobalNoticeNext::SponsorshipRollbackCheck.new(viewer: @user)
      assert_predicate check, :should_show_notice?
    end

    test "returns false if user has dismissed the notice" do
      @user.set_sponsorship_rollback_notification
      @user.dismiss_notice(:sponsorship_rollback)

      check = GlobalNoticeNext::SponsorshipRollbackCheck.new(viewer: @user)
      refute_predicate check, :should_show_notice?
    end

    test "returns false if user has no sponsorship rollback" do
      check = GlobalNoticeNext::SponsorshipRollbackCheck.new(viewer: @user)
      refute_predicate check, :should_show_notice?
    end
  end
end
