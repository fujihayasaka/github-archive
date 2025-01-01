# typed: true
# frozen_string_literal: true

require "test_helper"

unless GitHub.enterprise?
  class GlobalNoticeNext::SpammyOrgCheckTest < GitHub::TestCase
    fixtures do
      @user = create(:user, :verified, plan: "small")
    end

    context "#should_show_notice?" do
      test "returns true if user has a spammy org spammy" do
        org = create :organization, login: "sp4mm3rs", admin: @user
        org.spammy = true
        org.plan = nil
        org.save!
        org.reload

        assert org.spammy?

        check = GlobalNoticeNext::SpammyOrgsCheck.new(viewer: @user)

        assert check.should_show_notice?
      end

      test "returns false if user has no spammy orgs" do
        check = GlobalNoticeNext::SpammyCheck.new(viewer: @user)

        refute check.should_show_notice?
      end
    end
  end
end
