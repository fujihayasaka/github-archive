# typed: true
# frozen_string_literal: true

require "test_helper"

# global notice yet doesn't support enterprise yet
unless GitHub.enterprise?
  class GlobalNoticeNextTest < GitHub::TestCase
    self.strict_fixtures = true
    fixtures do
      @user = create(:user, :verified)
    end

    context "#current_notice_name" do
      test "returns nil when there is no current notice" do
        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice_name
      end

      test "returns current notice when there is a notice set" do
        GlobalNoticeNext.new(viewer: @user).set_notice(:spammy)

        assert_equal :spammy, GlobalNoticeNext.new(viewer: @user).current_notice_name
      end

      test "returns nil if notice has been unset" do
        GlobalNoticeNext.new(viewer: @user).set_notice(:spammy)
        @user.global_notice.unset

        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice_name
      end
    end

    context "#current_notice" do
      test "returns nil when there is no current notice" do
        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice
      end

      test "returns an instance of the current notice check there is a notice set" do
        GlobalNoticeNext.new(viewer: @user).set_notice(:spammy)

        assert_equal GlobalNoticeNext::SpammyCheck, GlobalNoticeNext.new(viewer: @user).current_notice.class
      end

      test "returns nil if notice has been unset" do
        GlobalNoticeNext.new(viewer: @user).set_notice(:spammy)
        @user.global_notice.unset

        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice
      end
    end

    context "#set_notice" do
      test "overrides notice if notice has higher priority" do
        GlobalNoticeNext.new(viewer: @user).set_notice(:spammy_orgs)

        assert_equal :spammy_orgs, GlobalNoticeNext.new(viewer: @user).current_notice_name

        # spammy comes before spammy orgs, so it should be
        # overridden
        GlobalNoticeNext.new(viewer: @user).set_notice(:spammy)

        assert_equal :spammy, GlobalNoticeNext.new(viewer: @user).current_notice_name
      end

      test "does not override notice if notice has lower priority" do
        GlobalNoticeNext.new(viewer: @user).set_notice(:spammy)

        assert_equal :spammy, GlobalNoticeNext.new(viewer: @user).current_notice_name

        # spammy comes before spammy_orgs, so it should not be
        # overridden
        GlobalNoticeNext.new(viewer: @user).set_notice(:spammy_orgs)

        assert_equal :spammy, GlobalNoticeNext.new(viewer: @user).current_notice_name
      end

      test "sets notice if notice name is included in notice list" do
        GlobalNoticeNext.new(viewer: @user).set_notice(:spammy)

        assert_equal :spammy, GlobalNoticeNext.new(viewer: @user).current_notice_name
      end

      test "raises if notice name isn't included in notice list" do
        assert_raises ArgumentError do
          GlobalNoticeNext.new(viewer: @user).set_notice(:fake)
        end
      end
    end

    context "#refresh" do
      test "unsets global notice if no notices should be set" do
        global_notice = GlobalNoticeNext.new(viewer: @user)
        global_notice.set_notice(:spammy)

        @user.global_notice.refresh

        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice_name
      end

      test "sets global notice to new notice if notice should be set" do
        # Create spammy org so spammy_orgs notice is set
        create(:organization, admin: @user, spammy: true)

        GlobalNoticeNext.new(viewer: @user).set_notice(:spammy)
        @user.global_notice.refresh

        assert_equal :spammy_orgs, GlobalNoticeNext.new(viewer: @user).current_notice_name
      end
    end

    context "#never_been_set?" do
      test "returns true if user has never had a global notice" do
        assert GlobalNoticeNext.new(viewer: @user).never_been_set?
      end

      test "returns false if user has had a global notice" do
        GlobalNoticeNext.new(viewer: @user).set_notice(:spammy)

        refute GlobalNoticeNext.new(viewer: @user).never_been_set?
      end
    end
  end
end
