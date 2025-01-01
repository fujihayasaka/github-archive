# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class SuspendTest < GitHub::TestCase
    include HydroTestHelpers

    fixtures do
      @staffer = create(:staff_admin_user, login: "staffer", plan: "medium", email: "staffer@example.com")
    end

    test "enqueues job to update follower and following counts" do
      user = create(:user)
      CalculateFolloweringsCountJob.expects(:enqueue_once_per_interval).
        with(args: [user.id, true], interval: User::FollowDependency::FOLLOW_CALCULATION_INTERVAL_IN_SECONDS)
      user.suspend("Reasons")
    end

    test "hides users when suspended" do
      user = create(:user)
      perform_enqueued_jobs(only: [ToggleHiddenUserInNotificationsJob]) do
        user.suspend "Reasons"
      end

      assert Newsies::HiddenUser.where(user_id: user.id).exists?
    end

    test "instruments suspend" do
      events = subscribe "user.suspend"
      user = create(:user)
      user.suspend("reasons", actor: @staffer)

      expected_payload = {
        staff_actor: @staffer.login,
        staff_actor_id: @staffer.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
        reason: "reasons",
      }

      assert event = events.pop, "a user.suspend event was expected"
      assert_equal "user.suspend", event.name
      assert_equal event.payload.merge(expected_payload), event.payload
    end

    test "suspend publishes abuse classification hydro event" do
      now = Time.parse("2018-01-01")

      Timecop.freeze(now) do
        analyst = create :user, login: "triage-worker"
        user = create :user, login: "spammertime"

        user.suspend("testing", actor: analyst)

        message = {
          request_context: nil,
          actor: Hydro::EntitySerializer.user(analyst),
          account: Hydro::EntitySerializer.user(user),
          previous_classification: :NONE,
          current_classification: :NONE,
          previous_spammy_reason: { value: "" },
          current_spammy_reason: { value: "" },
          previously_suspended: { value: false },
          currently_suspended: { value: true },
          currently_deleted: { value: false },
          origin: :DOTCOM,
          queue_action: :QUEUE_ACTION_NONE,
          queue_entry: nil,
          previous_queue: nil,
          current_queue: nil,
          queued_time_in_seconds: nil,
        }

        assert_hydro_published(message, schema: "github.v1.AbuseClassification")
        assert_hydro_messages count: 1, schema: "github.v1.AbuseClassification"
      end
    end
  end
end
