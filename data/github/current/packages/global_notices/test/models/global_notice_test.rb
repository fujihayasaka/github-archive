# typed: true
# frozen_string_literal: true

require "test_helper"

# global notice yet doesn't support enterprise yet
unless GitHub.enterprise?
  class GlobalNoticeTest < GitHub::TestCase
    self.strict_fixtures = true
    fixtures do
      @user = create(:user, :verified)
    end

    test "handles creation race conditions" do
      other_notice = @user.global_notice
      @user.reload.global_notice.set(:spammy)

      assert_nothing_raised do
        other_notice.set(:billing_email)
      end

      assert_equal "billing_email", @user.reload.global_notice.name
    end

    context "#set?" do
      test "returns false if no notice has been set" do
        refute @user.global_notice.set?, "expected notice to not be set"
      end

      test "returns false if no notice has been set to :no_notice" do
        @user.global_notice.set(:spammy)
        @user.global_notice.refresh

        refute @user.global_notice.set?, "expected notice to not be set"
      end

      test "returns true if no notice has been set" do
        @user.global_notice.set(:spammy)
        assert @user.global_notice.reload.set?, "expected notice to be set"
      end
    end

    context "#notice" do
      test "returns nil when there is no current notice" do
        assert_nil @user.global_notice.notice
      end

      test "returns an instance of the current notice check there is a notice set" do
        @user.global_notice.set("spammy")

        assert_equal GlobalNoticeNext::SpammyCheck, @user.global_notice.reload.notice.class
      end

      test "returns nil if notice has been unset" do
        @user.global_notice.set("spammy")
        @user.global_notice.unset

        assert_nil @user.global_notice.notice
      end
    end

    context "#set_notice" do
      test "overrides notice if notice has higher priority" do
        @user.global_notice.set("spammy_orgs")

        assert_equal "spammy_orgs", @user.global_notice.reload.name

        # spammy comes before spammy orgs, so it should be
        # overridden
        @user.global_notice.set("spammy")

        assert_equal "spammy", @user.global_notice.reload.name
      end

      test "does not override notice if notice has lower priority" do
        @user.global_notice.set("spammy")

        assert_equal "spammy", @user.global_notice.reload.name

        # spammy comes before spammy_orgs, so it should not be
        # overridden
        @user.global_notice.set("spammy")

        assert_equal "spammy", @user.global_notice.reload.name
      end

      test "sets notice if notice name is included in notice list" do
        @user.global_notice.set("spammy")

        assert_equal "spammy", @user.global_notice.reload.name
      end

      test "raises if notice name isn't included in notice list" do
        assert_raises ArgumentError do
          @user.global_notice.set(:fake)
        end
      end

      test "doesn't update last_checked_at" do
        GlobalNoticeNext.new(viewer: @user).set_notice(:spammy)
        assert_nil @user.global_notice.last_checked_at
      end
    end

    context "#refresh" do
      test "unsets global notice if no notices should be set" do
        @user.global_notice.set("spammy")

        @user.global_notice.refresh

        refute @user.global_notice.reload.set?, "expected notice to be unset"
      end

      test "sets global notice to new notice if notice should be set" do
        # Create spammy org so spammy_orgs notice is set
        create(:organization, admin: @user, spammy: true)

        @user.global_notice.set("spammy")
        @user.global_notice.refresh

        assert_equal "spammy_orgs", @user.global_notice.reload.name
      end

      test "updates last_checked_at" do
        now = Time.now
        Timecop.freeze(now) do
          @user.global_notice.refresh
          assert_equal @user.global_notice.last_checked_at.to_i, now.to_i
        end
      end
    end
  end
end
