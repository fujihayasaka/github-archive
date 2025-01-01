# typed: true
# frozen_string_literal: true

require "test_helper"

unless GitHub.enterprise?
  class GlobalNoticeNext::SpammyCheckTest < GitHub::TestCase
    fixtures do
      @user = create(:user, :verified, plan: "small")
    end

    context "#should_show_notice?" do
      test "returns true if user is spammy" do
        @user.spammy = true
        @user.save

        check = GlobalNoticeNext::SpammyCheck.new(viewer: @user)

        assert check.should_show_notice?
      end

      test "returns false if user is not spammy" do
        check = GlobalNoticeNext::SpammyCheck.new(viewer: @user)

        refute check.should_show_notice?
      end
    end
  end
end
