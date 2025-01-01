# typed: true
# frozen_string_literal: true
require "test_helper"

class SpamQueueEntryTest < GitHub::TestCase
  fixtures do
    @triage_worker = create :user, login: "triage-worker"
    @user_to_investigate = create :user, login: "spammertime"
    @queue = create :spam_queue, name: "user_triage"
    @issue = create(:issue)
  end

  test "#user= sets the user_login" do
    user = create :user, login: "loggy"
    sqe = SpamQueueEntry.new user: user
    assert_equal user, sqe.user
    assert_equal "loggy", sqe.user_login
  end

  context "moving an entry to the end of the queue" do
    test "destroys the record" do
      sqe = @queue.entries.create user: @user_to_investigate,
        added_by: @triage_worker,
        spam_source: @issue,
        spam_queue: @queue,
        additional_context: "Foo Bar Baz"

      sqe.move_to_end_of_queue

      refute SpamQueueEntry.exists?(sqe.id)
    end

    test "creates a new record with all the same attributes" do
      sqe = @queue.entries.create user: @user_to_investigate,
        added_by: @triage_worker,
        spam_source: @issue,
        spam_queue: @queue,
        additional_context: "Foo Bar Baz"

      new_entry = sqe.move_to_end_of_queue
      refute_equal sqe.id, new_entry.id

      old_attrs = sqe.attributes.except "id"
      new_attrs = new_entry.attributes.except "id"
      assert_equal old_attrs, new_attrs
    end
  end

  context "dropping an entry" do
    test "destroys the record" do
      sqe = @queue.entries.create user: @user_to_investigate,
        added_by: @triage_worker,
        spam_source: @issue,
        spam_queue: @queue,
        additional_context: "Foo Bar Baz"

      sqe.drop actor: @triage_worker

      refute SpamQueueEntry.exists?(sqe.id)
    end

    test "instruments the drop" do
      events = subscribe "spam_queue_entry.drop"
      sqe = @queue.entries.create user: @user_to_investigate,
        added_by: @triage_worker,
        spam_source: @issue,
        spam_queue: @queue,
        additional_context: "Foo Bar Baz"

      triage_worker2 = create :user, login: "triagebill"
      sqe.stubs(:queued_time_in_seconds).returns(5)
      sqe.drop actor: triage_worker2

      expected_payload = {
        spam_queue_entry_id: sqe.id,
        queue_name: "user_triage",
        user: "spammertime",
        user_id: @user_to_investigate.id,
        additional_context: "Foo Bar Baz",
        added_by: "triage-worker",
        added_by_id: @triage_worker.id,
        actor: "triagebill",
        actor_id: triage_worker2.id,
        queued_time_in_seconds: 5,
      }

      assert event = events.pop, "expected an instrumentation event"
      assert_equal expected_payload, event.payload.slice(*expected_payload.keys)
    end
  end

  if GitHub.spamminess_check_enabled?
    context "resolving an entry as spammy" do
      test "destroys the queue entry" do
        sqe = @queue.entries.create user: @user_to_investigate, spam_queue: @queue
        sqe.resolve_as_spammy actor: @triage_worker, reason: "Country specific spammer"

        refute SpamQueueEntry.exists?(sqe.id)
      end

      test "marks the user as spammy" do
        refute @user_to_investigate.spammy?
        sqe = @queue.entries.create user: @user_to_investigate, spam_queue: @queue
        sqe.resolve_as_spammy actor: @triage_worker, reason: "Country specific spammer"

        assert @user_to_investigate.reload.spammy?
        assert_equal "Country specific spammer by @triage-worker",  @user_to_investigate.spammy_reason
      end

      test "hard flagging the user modifies the reason" do
        refute @user_to_investigate.spammy?
        sqe = @queue.entries.create user: @user_to_investigate, spam_queue: @queue
        sqe.resolve_as_spammy actor: @triage_worker, reason: "Country specific spammer", hard_flag: true

        assert @user_to_investigate.reload.spammy?
        assert_equal "Country specific spammer by @triage-worker [octocat approved]",  @user_to_investigate.spammy_reason
      end

      test "does not instrument if the user has been deleted" do
        refute @user_to_investigate.spammy?
        sqe = @queue.entries.create user: @user_to_investigate, spam_queue: @queue
        @user_to_investigate.destroy

        events = subscribe "spam_queue_entry.resolved"
        sqe.resolve_as_spammy actor: @triage_worker, reason: "Country specific spammer"

        refute event = events.pop, "expected no instrumentation events"
      end

      test "does not attempt to mark spammy if the user has been deleted" do
        refute @user_to_investigate.spammy?
        sqe = @queue.entries.create user: @user_to_investigate, spam_queue: @queue
        sqe.user.expects(:mark_as_spammy).never
        @user_to_investigate.destroy

        sqe.resolve_as_spammy actor: @triage_worker, reason: "Country specific spammer"
      end

      test "instruments #resolve_as_spammy" do
        events = subscribe "spam_queue_entry.resolved"
        sqe = @queue.entries.create user: @user_to_investigate,
          added_by: @triage_worker,
          spam_source: @issue,
          spam_queue: @queue,
          additional_context: "Foo Bar Baz"

        triage_worker2 = create :user, login: "triagebill"
        sqe.stubs(:queued_time_in_seconds).returns(5)
        sqe.resolve_as_spammy actor: triage_worker2,
          reason: "Country specific spammer"

        expected_payload = {
          resolution: :flag_as_spam,
          spam_queue_entry_id: sqe.id,
          queue_name: "user_triage",
          user: "spammertime",
          user_id: @user_to_investigate.id,
          additional_context: "Foo Bar Baz",
          added_by: "triage-worker",
          added_by_id: @triage_worker.id,
          actor: "triagebill",
          actor_id: triage_worker2.id,
          queued_time_in_seconds: 5,
          reason: "Country specific spammer",
          hard_flag: false,
        }

        assert event = events.pop, "expected an instrumentation event"
        assert_equal expected_payload, event.payload.slice(*expected_payload.keys)
      end
    end

    context "resolving an entry as whitelisted" do
      test "destroys the queue entry" do
        sqe = @queue.entries.create user: @user_to_investigate, spam_queue: @queue
        sqe.resolve_as_whitelisted actor: @triage_worker

        refute SpamQueueEntry.exists?(sqe.id)
      end

      test "whitelists the user" do
        refute @user_to_investigate.hammy?
        sqe = @queue.entries.create user: @user_to_investigate, spam_queue: @queue
        sqe.resolve_as_whitelisted actor: @triage_worker

        assert @user_to_investigate.reload.hammy?
        assert_equal "Not spammy",  @user_to_investigate.spammy_reason
      end

      test "does not instrument if the user has been deleted" do
        refute @user_to_investigate.hammy?
        sqe = @queue.entries.create user: @user_to_investigate, spam_queue: @queue
        @user_to_investigate.destroy

        events = subscribe "spam_queue_entry.resolved"
        sqe.resolve_as_whitelisted actor: @triage_worker

        refute event = events.pop, "expected no instrumentation events"
      end

      test "does not attempt to whitelist if the user has been deleted" do
        refute @user_to_investigate.hammy?
        sqe = @queue.entries.create user: @user_to_investigate, spam_queue: @queue
        sqe.user.expects(:mark_not_spammy).never
        @user_to_investigate.destroy

        sqe.resolve_as_whitelisted actor: @triage_worker
      end

      test "instruments #resolve_as_whitelisted" do
        events = subscribe "spam_queue_entry.resolved"
        sqe = @queue.entries.create user: @user_to_investigate,
          added_by: @triage_worker,
          spam_source: @issue,
          spam_queue: @queue,
          additional_context: "Foo Bar Baz"

        triage_worker2 = create :user, login: "triagebill"
        sqe.stubs(:queued_time_in_seconds).returns(5)
        sqe.resolve_as_whitelisted actor: triage_worker2

        expected_payload = {
          resolution: :whitelist,
          spam_queue_entry_id: sqe.id,
          queue_name: "user_triage",
          user: "spammertime",
          user_id: @user_to_investigate.id,
          additional_context: "Foo Bar Baz",
          added_by: "triage-worker",
          added_by_id: @triage_worker.id,
          actor: "triagebill",
          actor_id: triage_worker2.id,
          queued_time_in_seconds: 5,
        }

        assert event = events.pop, "expected an instrumentation event"
        assert_equal expected_payload, event.payload.slice(*expected_payload.keys)
      end
    end

    context "resolving an entry as unflagged" do
      test "destroys the queue entry" do
        sqe = @queue.entries.create user: @user_to_investigate, spam_queue: @queue
        sqe.resolve_as_unflagged actor: @triage_worker

        refute SpamQueueEntry.exists?(sqe.id)
      end

      test "unflags the user" do
        @user_to_investigate.update spammy: true, spammy_reason: "SpamTimes"
        sqe = @queue.entries.create user: @user_to_investigate, spam_queue: @queue
        sqe.resolve_as_unflagged actor: @triage_worker

        refute @user_to_investigate.reload.spammy?
      end

      test "does not instrument if the user has been deleted" do
        @user_to_investigate.update spammy: true, spammy_reason: "SpamTimes"
        sqe = @queue.entries.create user: @user_to_investigate, spam_queue: @queue
        @user_to_investigate.destroy

        events = subscribe "spam_queue_entry.resolved"
        sqe.resolve_as_unflagged actor: @triage_worker

        refute event = events.pop, "expected no instrumentation events"
      end

      test "does not attempt to unflag if the user has been deleted" do
        @user_to_investigate.update spammy: true, spammy_reason: "SpamTimes"
        sqe = @queue.entries.create user: @user_to_investigate, spam_queue: @queue
        sqe.user.expects(:mark_not_spammy).never
        @user_to_investigate.destroy

        sqe.resolve_as_unflagged actor: @triage_worker
      end

      test "instruments #resolve_as_unflagged" do
        @user_to_investigate.update spammy: true, spammy_reason: "SpamTimes"
        events = subscribe "spam_queue_entry.resolved"
        sqe = @queue.entries.create user: @user_to_investigate,
          added_by: @triage_worker,
          spam_source: @issue,
          spam_queue: @queue,
          additional_context: "Foo Bar Baz"

        triage_worker2 = create :user, login: "triagebill"
        sqe.stubs(:queued_time_in_seconds).returns(5)
        sqe.resolve_as_unflagged actor: triage_worker2

        expected_payload = {
          resolution: :unflag_as_spam,
          spam_queue_entry_id: sqe.id,
          queue_name: "user_triage",
          user: "spammertime",
          user_id: @user_to_investigate.id,
          additional_context: "Foo Bar Baz",
          added_by: "triage-worker",
          added_by_id: @triage_worker.id,
          actor: "triagebill",
          actor_id: triage_worker2.id,
          queued_time_in_seconds: 5,
        }

        assert event = events.pop, "expected an instrumentation event"
        assert_equal expected_payload, event.payload.slice(*expected_payload.keys)
      end
    end
  end

  context "#platform_move_to_queue" do
    test "moves the entry to the queue" do
      sqe = @queue.entries.create user: @user_to_investigate, spam_queue: @queue
      new_queue = create :spam_queue

      assert_difference("@queue.entries.count", -1) do
        assert_difference("new_queue.entries.count") do
          new_sqe = sqe.platform_move_to_queue(
            new_queue: new_queue,
            actor: @triage_worker,
          )

          assert_equal new_queue, new_sqe.spam_queue
        end
      end
    end
  end

  context "moving to a new queue" do
    test "moves the entry to the queue" do
      sqe = @queue.entries.create user: @user_to_investigate, spam_queue: @queue
      new_queue = create :spam_queue

      sqe.move_to_queue new_queue: new_queue,
        actor: @triage_worker,
        reason: "Further inspection"

      assert_equal new_queue, sqe.reload.spam_queue
    end

    test "can move without actor" do
      sqe = @queue.entries.create user: @user_to_investigate, spam_queue: @queue
      new_queue = create :spam_queue

      sqe.move_to_queue new_queue: new_queue, reason: "Further inspection"

      assert_equal new_queue, sqe.reload.spam_queue
    end

    test "can move without reason" do
      sqe = @queue.entries.create user: @user_to_investigate, spam_queue: @queue
      new_queue = create :spam_queue

      sqe.move_to_queue new_queue: new_queue

      assert_equal new_queue, sqe.reload.spam_queue
    end

    test "instruments #move_to_queue" do
      events = subscribe "spam_queue_entry.move"
      sqe = @queue.entries.create user: @user_to_investigate,
        added_by: @triage_worker,
        spam_source: @issue,
        spam_queue: @queue,
        additional_context: "Foo Bar Baz"

      new_queue = create :spam_queue, name: "new_queue"
      triage_worker2 = create :user, login: "triagebill"
      sqe.stubs(:queued_time_in_seconds).returns(5)
      sqe.move_to_queue new_queue: new_queue,
        actor: triage_worker2,
        reason: "Further inspection"

      expected_payload = {
        spam_queue_entry_id: sqe.id,
        queue_name: "new_queue",
        user: "spammertime",
        user_id: @user_to_investigate.id,
        additional_context: "Foo Bar Baz",
        added_by: "triage-worker",
        added_by_id: @triage_worker.id,
        actor: "triagebill",
        actor_id: triage_worker2.id,
        queued_time_in_seconds: 5,
        reason: "Further inspection",
        old_queue_name: "user_triage",
        resolution: :move_queue,
      }

      assert event = events.pop, "expected an instrumentation event"
      assert_equal expected_payload, event.payload.slice(*expected_payload.keys)
    end
  end

  test "instruments creation" do
    events = subscribe "spam_queue_entry.create"
    sqe = @queue.entries.create user: @user_to_investigate,
      added_by: @triage_worker,
      spam_source: @issue,
      spam_queue: @queue,
      additional_context: "Foo Bar Baz"

    expected_payload = {
      spam_queue_entry_id: sqe.id,
      queue_name: "user_triage",
      user: "spammertime",
      user_id: @user_to_investigate.id,
      additional_context: "Foo Bar Baz",
      added_by: "triage-worker",
      added_by_id: @triage_worker.id,
    }

    assert event = events.pop, "expected an instrumentation event"
    assert_equal expected_payload, event.payload.slice(*expected_payload.keys)
  end

  test "instruments deletion" do
    events = subscribe "spam_queue_entry.destroy"
    sqe = @queue.entries.create user: @user_to_investigate,
      added_by: @triage_worker,
      spam_source: @issue,
      spam_queue: @queue,
      additional_context: "Foo Bar Baz"

    sqe.destroy

    expected_payload = {
      spam_queue_entry_id: sqe.id,
      queue_name: "user_triage",
      user: "spammertime",
      user_id: @user_to_investigate.id,
      additional_context: "Foo Bar Baz",
      added_by: "triage-worker",
      added_by_id: @triage_worker.id,
    }

    assert event = events.pop, "expected an instrumentation event"
    assert_equal expected_payload, event.payload.slice(*expected_payload.keys)
  end
end

class AbuseClassificationHydroEventsTest < GitHub::TestCase
  include HydroTestHelpers

  test "spam_queue_entry.create" do
    now = Time.parse("2018-01-01")

    Timecop.freeze(now) do
      analyst = create :user, login: "triage-worker"
      user_to_investigate = create :user, login: "spammertime"
      current_queue = create :spam_queue, name: "current_queue"

      sqe = current_queue.entries.create({
        user: user_to_investigate,
        added_by: analyst,
        spam_queue: current_queue,
        additional_context: "Foo Bar Baz",
      })

      message = {
        request_context: nil,
        actor: Hydro::EntitySerializer.user(analyst),
        account: Hydro::EntitySerializer.user(user_to_investigate),
        previous_classification: :NONE,
        current_classification: :NONE,
        previous_spammy_reason: { value: "" },
        current_spammy_reason: { value: "" },
        previously_suspended: { value: false },
        currently_suspended: { value: false },
        currently_deleted: { value: false },
        origin: :DOTCOM,
        queue_action: :ADD,
        queue_entry: Hydro::EntitySerializer.spam_queue_entry(sqe),
        previous_queue: nil,
        current_queue: Hydro::EntitySerializer.spam_queue(current_queue),
        queued_time_in_seconds: { value: 0 },
      }

      assert_hydro_published(message, schema: "github.v1.AbuseClassification")
      assert_hydro_messages count: 1, schema: "github.v1.AbuseClassification"
    end
  end

  test "spam_queue_entry.move when user has been deleted" do
    now = Time.parse("2018-01-01")

    Timecop.freeze(now) do
      analyst = create :user, login: "triage-worker"
      user_to_investigate = create :user, login: "spammertime"
      current_queue = create :spam_queue, name: "current_queue"
      new_queue = create :spam_queue, name: "new_queue"

      sqe = current_queue.entries.create({
        user: user_to_investigate,
        added_by: analyst,
        spam_queue: current_queue,
        additional_context: "Foo Bar Baz",
      })
      sqe.stubs(:queued_time_in_seconds).returns(5.1)

      user_to_investigate.destroy

      sqe.reload

      sqe.move_to_queue new_queue: new_queue,
        actor: analyst,
        reason: "Further inspection"

      deleted_user = User.new.tap { |user| user.id = sqe.user_id; user.login = sqe.user_login }

      message = {
        request_context: nil,
        actor: Hydro::EntitySerializer.user(analyst),
        account: Hydro::EntitySerializer.user(deleted_user),
        previous_classification: nil,
        current_classification: nil,
        previous_spammy_reason: nil,
        current_spammy_reason: nil,
        previously_suspended: nil,
        currently_suspended: nil,
        currently_deleted: { value: true },
        origin: :DOTCOM,
        queue_action: :MOVE_QUEUES,
        queue_entry: Hydro::EntitySerializer.spam_queue_entry(sqe),
        previous_queue: Hydro::EntitySerializer.spam_queue(current_queue),
        current_queue: Hydro::EntitySerializer.spam_queue(new_queue),
        queued_time_in_seconds: { value: 5 },
      }

      assert_hydro_published(message, schema: "github.v1.AbuseClassification")
      assert_hydro_messages count: 2, schema: "github.v1.AbuseClassification"
    end
  end

  test "spam_queue_entry.resolved flag_as_spam" do
    now = Time.parse("2018-01-01")

    Timecop.freeze(now) do
      analyst = create :user, login: "triage-worker"
      user_to_investigate = create :user, login: "spammertime"
      current_queue = create :spam_queue, name: "current_queue"

      sqe = current_queue.entries.create({
        user: user_to_investigate,
        added_by: analyst,
        spam_queue: current_queue,
        additional_context: "Foo Bar Baz",
      })
      sqe.stubs(:queued_time_in_seconds).returns(5.1)
      GitHub.stubs(:component).returns(:console)
      sqe.resolve_as_spammy(reason: "bad actor", actor: analyst)

      message = {
        request_context: nil,
        actor: Hydro::EntitySerializer.user(analyst),
        account: Hydro::EntitySerializer.user(user_to_investigate),
        previous_classification: :NONE,
        current_classification: :SPAMMY,
        previous_spammy_reason: { value: "" },
        current_spammy_reason: { value: "bad actor by @triage-worker" },
        previously_suspended: { value: false },
        currently_suspended: { value: false },
        currently_deleted: { value: false },
        origin: :CONSOLE,
        queue_action: :UNQUEUE,
        queue_entry: nil,
        previous_queue: Hydro::EntitySerializer.spam_queue(current_queue),
        current_queue: nil,
        queued_time_in_seconds: { value: 5 },
      }

      assert_hydro_published(message, schema: "github.v1.AbuseClassification")

      # ensure no extra event is published when calling mark_as_spammy or mark_not_spammy
      assert_hydro_messages count: 2, schema: "github.v1.AbuseClassification"
    end
  end

  test "spam_queue_entry.resolved unflag" do
    now = Time.parse("2018-01-01")

    Timecop.freeze(now) do
      analyst = create :user, login: "triage-worker"
      user_to_investigate = create :user, login: "spammertime"
      current_queue = create :spam_queue, name: "current_queue"

      sqe = current_queue.entries.create({
        user: user_to_investigate,
        added_by: analyst,
        spam_queue: current_queue,
        additional_context: "Foo Bar Baz",
      })
      sqe.stubs(:queued_time_in_seconds).returns(5.1)
      sqe.resolve_as_unflagged(actor: analyst, origin: :spamurai)

      message = {
        request_context: nil,
        actor: Hydro::EntitySerializer.user(analyst),
        account: Hydro::EntitySerializer.user(user_to_investigate),
        previous_classification: :NONE,
        current_classification: :NONE,
        previous_spammy_reason: { value: "" },
        current_spammy_reason: { value: "" },
        previously_suspended: { value: false },
        currently_suspended: { value: false },
        currently_deleted: { value: false },
        origin: :SPAMURAI,
        queue_action: :UNQUEUE,
        queue_entry: nil,
        previous_queue: Hydro::EntitySerializer.spam_queue(current_queue),
        current_queue: nil,
        queued_time_in_seconds: { value: 5 },
      }

      assert_hydro_published(message, schema: "github.v1.AbuseClassification")

      # ensure no extra event is published when calling mark_as_spammy or mark_not_spammy
      assert_hydro_messages count: 2, schema: "github.v1.AbuseClassification"
    end
  end

  test "spam_queue_entry.resolved whitelist" do
    now = Time.parse("2018-01-01")

    Timecop.freeze(now) do
      analyst = create :user, login: "triage-worker"
      user_to_investigate = create :user, login: "spammertime"
      current_queue = create :spam_queue, name: "current_queue"

      sqe = current_queue.entries.create({
        user: user_to_investigate,
        added_by: analyst,
        spam_queue: current_queue,
        additional_context: "Foo Bar Baz",
      })
      sqe.stubs(:queued_time_in_seconds).returns(5.1)
      GitHub.stubs(:component).returns(:console)
      sqe.resolve_as_whitelisted(actor: analyst)

      message = {
        request_context: nil,
        actor: Hydro::EntitySerializer.user(analyst),
        account: Hydro::EntitySerializer.user(user_to_investigate),
        previous_classification: :NONE,
        current_classification: :HAMMY,
        previous_spammy_reason: { value: "" },
        current_spammy_reason: { value: "Not spammy" },
        previously_suspended: { value: false },
        currently_suspended: { value: false },
        currently_deleted: { value: false },
        origin: :CONSOLE,
        queue_action: :UNQUEUE,
        queue_entry: nil,
        previous_queue: Hydro::EntitySerializer.spam_queue(current_queue),
        current_queue: nil,
        queued_time_in_seconds: { value: 5 },
      }

      assert_hydro_published(message, schema: "github.v1.AbuseClassification")

      # ensure no extra event is published when calling mark_as_spammy or mark_not_spammy
      assert_hydro_messages count: 2, schema: "github.v1.AbuseClassification"
    end
  end

  test "spam_queue_entry.platform_move_to_queue" do
    now = Time.parse("2018-01-01")

    Timecop.freeze(now) do
      analyst = create :user, login: "triage-worker"
      user_to_investigate = create :user, login: "spammertime"
      current_queue = create :spam_queue, name: "current_queue"
      new_queue = create :spam_queue, name: "new_queue"

      sqe = current_queue.entries.create({
        user: user_to_investigate,
        added_by: analyst,
        spam_queue: current_queue,
        additional_context: "Foo Bar Baz",
      })

      sqe.stubs(:queued_time_in_seconds).returns(5.1)
      new_sqe = sqe.platform_move_to_queue(
        new_queue: new_queue,
        actor: analyst,
      )

      message = {
        request_context: nil,
        actor: Hydro::EntitySerializer.user(analyst),
        account: Hydro::EntitySerializer.user(user_to_investigate),
        previous_classification: :NONE,
        current_classification: :NONE,
        previous_spammy_reason: { value: "" },
        current_spammy_reason: { value: "" },
        previously_suspended: { value: false },
        currently_suspended: { value: false },
        currently_deleted: { value: false },
        origin: :DOTCOM,
        queue_action: :MOVE_QUEUES,
        queue_entry: Hydro::EntitySerializer.spam_queue_entry(new_sqe),
        previous_queue: Hydro::EntitySerializer.spam_queue(current_queue),
        current_queue: Hydro::EntitySerializer.spam_queue(new_queue),
        queued_time_in_seconds: { value: 5 },
      }

      assert_hydro_published(message, schema: "github.v1.AbuseClassification")
      assert_hydro_messages count: 2, schema: "github.v1.AbuseClassification"
    end
  end

  test "spam_queue_entry.drop" do
    now = Time.parse("2018-01-01")

    Timecop.freeze(now) do
      analyst = create :user, login: "triage-worker"
      user_to_investigate = create :user, login: "spammertime"
      current_queue = create :spam_queue, name: "current_queue"

      sqe = current_queue.entries.create({
        user: user_to_investigate,
        added_by: analyst,
        spam_queue: current_queue,
        additional_context: "Foo Bar Baz",
      })
      sqe.stubs(:queued_time_in_seconds).returns(5.1)
      sqe.drop(actor: analyst)

      message = {
        request_context: nil,
        actor: Hydro::EntitySerializer.user(analyst),
        account: Hydro::EntitySerializer.user(user_to_investigate),
        previous_classification: :NONE,
        current_classification: :NONE,
        previous_spammy_reason: { value: "" },
        current_spammy_reason: { value: "" },
        previously_suspended: { value: false },
        currently_suspended: { value: false },
        currently_deleted: { value: false },
        origin: :DOTCOM,
        queue_action: :UNQUEUE,
        queue_entry: nil,
        previous_queue: Hydro::EntitySerializer.spam_queue(current_queue),
        current_queue: nil,
        queued_time_in_seconds: { value: 5 },
      }

      assert_hydro_published(message, schema: "github.v1.AbuseClassification")
      assert_hydro_messages count: 2, schema: "github.v1.AbuseClassification"
    end
  end

  test "spam_queue_entry.move_to_end_of_queue" do
    now = Time.parse("2018-01-01")

    Timecop.freeze(now) do
      analyst = create :user, login: "triage-worker"
      user_to_investigate = create :user, login: "spammertime"
      current_queue = create :spam_queue, name: "current_queue"

      sqe = current_queue.entries.create({
        user: user_to_investigate,
        added_by: analyst,
        spam_queue: current_queue,
        additional_context: "Foo Bar Baz",
      })

      sqe.stubs(:queued_time_in_seconds).returns(5.1)
      new_sqe = sqe.move_to_end_of_queue

      message = {
        request_context: nil,
        actor: Hydro::EntitySerializer.user(analyst),
        account: Hydro::EntitySerializer.user(user_to_investigate),
        previous_classification: :NONE,
        current_classification: :NONE,
        previous_spammy_reason: { value: "" },
        current_spammy_reason: { value: "" },
        previously_suspended: { value: false },
        currently_suspended: { value: false },
        currently_deleted: { value: false },
        origin: :DOTCOM,
        queue_action: :PUSH_TO_END,
        queue_entry: Hydro::EntitySerializer.spam_queue_entry(new_sqe),
        previous_queue: Hydro::EntitySerializer.spam_queue(current_queue),
        current_queue: Hydro::EntitySerializer.spam_queue(current_queue),
        queued_time_in_seconds: { value: 5 },
      }

      assert_hydro_published(message, schema: "github.v1.AbuseClassification")
      assert_hydro_messages count: 2, schema: "github.v1.AbuseClassification"
    end
  end

  test "spam_queue_entry.resolve drop when user has been deleted" do
    now = Time.parse("2018-01-01")

    Timecop.freeze(now) do
      analyst = create :user, login: "triage-worker"
      user_to_investigate = create :user, login: "spammertime"
      current_queue = create :spam_queue, name: "current_queue"

      sqe = current_queue.entries.create({
        user: user_to_investigate,
        added_by: analyst,
        spam_queue: current_queue,
        additional_context: "Foo Bar Baz",
      })
      sqe.stubs(:queued_time_in_seconds).returns(5.1)

      user_to_investigate.destroy

      sqe.reload

      sqe.resolve(actor: analyst, classification: :spammy)

      deleted_user = User.new.tap { |user| user.id = sqe.user_id; user.login = sqe.user_login }

      message = {
        request_context: nil,
        actor: Hydro::EntitySerializer.user(analyst),
        account: Hydro::EntitySerializer.user(deleted_user),
        previous_classification: nil,
        current_classification: nil,
        previous_spammy_reason: nil,
        current_spammy_reason: nil,
        previously_suspended: nil,
        currently_suspended: nil,
        currently_deleted: { value: true },
        origin: :DOTCOM,
        queue_action: :UNQUEUE,
        queue_entry: nil,
        previous_queue: Hydro::EntitySerializer.spam_queue(current_queue),
        current_queue: nil,
        queued_time_in_seconds: { value: 5 },
      }

      assert_hydro_published(message, schema: "github.v1.AbuseClassification")
      assert_hydro_messages count: 2, schema: "github.v1.AbuseClassification"
    end
  end


end if GitHub.spamminess_check_enabled?
