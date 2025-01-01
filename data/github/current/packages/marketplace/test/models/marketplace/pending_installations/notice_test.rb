# typed: true
# frozen_string_literal: true

require "test_helper"

class MarketplacePendingInstallationsNoticeTest < GitHub::TestCase
  include ActiveSupport::Testing::TimeHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @notice = Marketplace::PendingInstallations::Notice.new(user_id: @user.id)
  end

  context "#dismiss" do
    test "marks the notice as dismissed" do
      refute @notice.dismissed?
      @notice.dismiss
      assert @notice.dismissed?
    end

    test "records the dismissal date" do
      freeze_time do
        refute @notice.dismissed_at
        @notice.dismiss
        assert_equal Time.current, @notice.dismissed_at
      end
    end
  end

  context "#dismissed?" do
    test "returns true when notice has been dismissed" do
      @notice.dismiss
      assert @notice.dismissed?
    end

    test "returns false when notice hasn't been dismissed" do
      refute @notice.dismissed?
    end
  end

  context "#dismissed_at" do
    test "returns nil when not set" do
      refute @notice.dismissed_at
    end

    test "returns date time value when set" do
      @notice.dismiss
      assert @notice.dismissed_at
    end
  end

  context "#reset" do
    test "clears notice dismissal" do
      @notice.dismiss
      assert @notice.dismissed?

      @notice.reset
      refute @notice.dismissed?
    end
  end
end
