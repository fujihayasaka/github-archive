# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::PersonalManualDunningCheckTest < GitHub::TestCase
  context "#should_show_notice?" do
    test "returns true if user is in manual dunning" do
      user = create :user, :manual_dunning, :verified

      check = GlobalNoticeNext::PersonalManualDunningCheck.new \
        viewer: user

      assert check.should_show_notice?
    end

    test "returns false if user is not in manual dunning" do
      user = create :user, :verified

      check = GlobalNoticeNext::PersonalManualDunningCheck.new \
        viewer: user

      refute check.should_show_notice?
    end
  end
end
