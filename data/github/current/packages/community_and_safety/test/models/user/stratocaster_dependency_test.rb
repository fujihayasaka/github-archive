# typed: true
# frozen_string_literal: true

require "test_helper"

class UserStratocasterDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  setup do
    GitHub.flipper[:discard_stratocaster_fanout].disable
  end

  context "clear_all_timelines" do
    test "clears user's public and private timelines" do
      repo = create(:repository)
      private_repo = create(:private_repository)
      user = private_repo.user
      timeline_key = "user:#{user.id}"

      user.watch_repo(repo)
      user.watch_repo(private_repo)
      public_repo_label = create(:label, name: Labelable::HELP_WANTED_NAME, repository: repo)
      private_repo_label = create(:label, name: Labelable::HELP_WANTED_NAME, repository: private_repo)
      only = [ProcessEventJob, UpdateEventFeedsJob]
      perform_enqueued_jobs(only: only) do
        @private_repo_issue = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: private_repo)
        @public_repo_issue = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: repo)
        @public_repo_issue.add_labels(public_repo_label)
        @private_repo_issue.add_labels(private_repo_label)
      end
      refute_empty Stratocaster::Timeline.for(timeline_key, user).events

      user.clear_all_timelines

      assert_empty Stratocaster::Timeline.for(timeline_key, user).events
    end

    test "instruments clear_all_timelines" do
      events = subscribe "user.clear_all_timelines"

      @user.clear_all_timelines

      assert event = events.pop, "a user.clear_all_timelines event was expected"
      assert_equal "user.clear_all_timelines", event.name
    end
  end

  context "last_stratocaster_event_at" do
    test "returns nil if there are no events" do
      user = create(:user)
      refute_predicate user.events, :any?
      assert_nil user.last_stratocaster_event_at, "should not have stratocaster event timestamp"
    end

    if GitHub.stratocaster_event_timestamp_cache_enabled?
      test "returns value from Feeds::KV if the most recent stratocaster event record has been deleted" do
        # Ensure 1 event exists in the timeline
        Timecop.freeze do
          perform_enqueued_jobs(only: [ProcessEventJob]) { create :repository, :full_creation, owner: @user }
        end

        # Simulate purging of the event record from the stratocaster event store, but not the index
        events = GitHub.stratocaster.ids(@user.events_key)
        GitHub.stratocaster.delete([events.first])

        GitHub.stratocaster.expects(:get).never

        from_github_kv = Feeds::KV.store.get(@user.stratocaster_event_timestamp_cache_key).value!
        assert_equal Time.parse(from_github_kv).in_time_zone, @user.last_stratocaster_event_at
      end
    else
      test "returns nil if the most recent stratocaster event record has been deleted" do
        # Ensure 1 event exists in the timeline
        Timecop.freeze do
          create :repository, owner: @user
        end

        # Simulate purging of the event record from the stratocaster event store, but not the index
        events = GitHub.stratocaster.ids(@user.events_key)
        GitHub.stratocaster.delete([events.first])

        assert_nil @user.last_stratocaster_event_at
      end
    end

    test "fails gracefully if stratocaster is unavailable" do
      GitHub.stratocaster.stubs(:ids).raises(Errno::ECONNREFUSED)
      assert_nil @user.last_stratocaster_event_at
    end

    test "returns date of the most recent event" do
      first_active_date = Time.rfc2822("Tue, 8 Jul 2008 17:40:30 -0700").utc
      last_active_date = Time.rfc2822("Tue, 15 Jul 2008 17:40:30 -0700").utc

      Timecop.freeze(first_active_date) do
        create :repository, owner: @user
      end

      Timecop.freeze(last_active_date) do
        only = [ProcessEventJob, UpdateEventFeedsJob]
        perform_enqueued_jobs(only: only) { create :repository, :full_creation, owner: @user }
      end

      assert_equal last_active_date.in_time_zone, @user.last_stratocaster_event_at
    end

    if GitHub.stratocaster_event_timestamp_cache_enabled?
      test "returns value from Feeds::KV if stratocaster event timestamp cache enabled" do

        first_active_date = Time.rfc2822("Tue, 8 Jul 2008 17:40:30 -0700").utc
        last_active_date = Time.rfc2822("Tue, 15 Jul 2008 17:40:30 -0700").utc

        Timecop.freeze(first_active_date) do
          create :repository, owner: @user
        end

        Timecop.freeze(last_active_date) do
          perform_enqueued_jobs(only: [ProcessEventJob]) { create :repository, :full_creation, owner: @user }
        end

        GitHub.stratocaster.expects(:get).never
        assert_equal last_active_date.in_time_zone, @user.last_stratocaster_event_at

        from_github_kv = Feeds::KV.store.get(@user.stratocaster_event_timestamp_cache_key).value!
        assert_equal Time.parse(from_github_kv).in_time_zone, @user.last_stratocaster_event_at
      end
    end
  end
end
