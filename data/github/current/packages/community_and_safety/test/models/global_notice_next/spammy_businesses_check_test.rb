# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::SpammyBusinessesCheckTest < GitHub::TestCase
  fixtures do
    @user = create :user, :verified, plan: "small"
  end

  context "#should_show_notice?" do
    test "returns true if user owns a spammy business" do
      business = create :business, owners: [@user]
      business.mark_as_spammy
      assert_predicate business, :spammy?

      check = GlobalNoticeNext::SpammyBusinessesCheck.new(viewer: @user)

      assert_predicate check, :should_show_notice?
    end

    test "returns false if user does not own any spammy businesses" do
      check = GlobalNoticeNext::SpammyCheck.new(viewer: @user)

      refute_predicate check, :should_show_notice?
    end
  end
end if GitHub.spamminess_check_enabled?
