# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::OrgManualDunningCheckTest < GitHub::TestCase
  fixtures do
    @user = create :user, :verified
  end

  context "#should_show_notice?" do
    test "returns true if a user owned org is in manual dunning" do
      create :organization, :manual_dunning, admin: @user

      check = GlobalNoticeNext::OrgManualDunningCheck.new \
        viewer: @user

      assert check.should_show_notice?
    end

    test "returns false if no user owned org is in manual dunning" do
      create :organization, admin: @user

      check = GlobalNoticeNext::OrgManualDunningCheck.new \
        viewer: @user

      refute check.should_show_notice?
    end
  end
end
