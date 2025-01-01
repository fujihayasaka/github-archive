# typed: true
# frozen_string_literal: true

require "test_helper"

module GlobalNotices
  class DomainTest < GitHub::TestCase
    extend TestHelpers::ContextHelpers

    fixtures { @user = create(:user) }

    sig { returns(User) }
    attr_reader :user

    context "#register" do
      test "raises when a notice with the same name is already registered" do
        assert_raises(ArgumentError) do
          # spammy is already registered by the app
          GlobalNotices.domain.register(:spammy) { |_| true }
        end
      end
    end

    context "#current_notice" do
      test "returns an empty notice if no notice has been set" do
        assert_equal "no_notice", GlobalNotices.domain.current_notice(user).name
      end

      test "returns the current notice if one has been set" do
        @user.update_column(:spammy, true)
        GlobalNotices.domain.set(user: @user, name: :spammy)

        assert_equal "spammy", GlobalNotices.domain.current_notice(user).name
      end

      test "returns an empty notice if the current notice is not registered" do
        notice = GlobalNotice.create(name: "spammy", user_id: @user.id)
        GlobalNotices::Registry.stubs(:instance).returns(Registry.new)

        assert_equal "no_notice", GlobalNotices.domain.current_notice(user).name
      end
    end

    context "#set" do
      test "returns true if the notice was set" do
        assert GlobalNotices.domain.set(user: @user, name: :spammy)
        assert_equal "spammy", GlobalNotices.domain.current_notice(user).name
      end

      test "overrides notice if notice has higher priority" do
        GlobalNotices.domain.set(user: @user, name: :spammy_orgs)

        assert_equal "spammy_orgs", GlobalNotices.domain.current_notice(user).name

        # spammy comes before spammy_orgs, so it should be overridden
        GlobalNotices.domain.set(user: @user, name: :spammy)

        assert_equal "spammy", GlobalNotices.domain.current_notice(user).name
      end

      test "does not override notice if current notice has higher priority" do
        GlobalNotices.domain.set(user: @user, name: :spammy)

        assert_equal "spammy", GlobalNotices.domain.current_notice(user).name

        # spammy comes before spammy_orgs, so it should not be overridden
        GlobalNotices.domain.set(user: @user, name: :spammy_orgs)

        assert_equal "spammy", GlobalNotices.domain.current_notice(user).name
      end

      test "sets notice if notice name is included in notice list" do
        @user.global_notice.set(:spammy)

        assert_equal "spammy", @user.global_notice.reload.name
      end

      test "raises if notice name isn't included in notice list" do
        assert_raises ArgumentError do
          GlobalNotices.domain.set(user: @user, name: :fake)
        end
      end
    end

    context "#refresh" do
      test "queues a background job in 5 minutes to refresh the global notice" do
        assert_enqueued_jobs 1, only: GlobalNoticeNextRefreshJob, queue: :global_notice_next_refresh do
          GlobalNotices.domain.refresh(T.must(user.id))
        end
      end
    end

    context "#snooze" do
      test "returns a not found result if the notice does not exist" do
        result = GlobalNotices.domain.snooze(user: @user, name: :spammy)
        assert_equal GH::Result::Error::NotFound, result.class
      end

      test "returns a not found result if the notice is not the current notice" do
        GlobalNotices.domain.set(user: @user, name: :spammy_orgs)
        result = GlobalNotices.domain.snooze(user: @user, name: :spammy)
        assert_equal GH::Result::Error::NotFound, result.class
      end

      test "returns a not found error if the notice is :no_notice" do
        GlobalNotices.domain.set(user: @user, name: :no_notice)
        result = GlobalNotices.domain.snooze(user: @user, name: :no_notice)
        assert_equal GH::Result::Error::NotFound, result.class
      end

      test "returns an argument error if the notice cannot be snoozed" do
        GlobalNotices.domain.set(user: @user, name: :spammy)
        result = GlobalNotices.domain.snooze(user: @user, name: :spammy)
        assert_equal GH::Result::Error::Argument, result.class
      end

      test "snoozes the notice if the notice can be snoozed" do
        GlobalNotices.domain.set(user: @user, name: :low_two_factor_methods)
        Timecop.freeze do
          now = Time.now
          GitHub::Authentication::KV.store.expects(:set).with(
            "user.dismissed_notice.low_two_factor_methods.#{user.id}",
            now.utc.iso8601,
            expires: 3.months.from_now
          )
          assert_predicate GlobalNotices.domain.snooze(user: @user, name: :low_two_factor_methods), :ok?
        end
      end
    end
  end
end
