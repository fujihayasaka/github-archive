# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class UnsuspendTest < GitHub::TestCase
    fixtures do
      @staffer = create(:staff_admin_user, login: "staffer", plan: "medium", email: "staffer@example.com")
    end

    test "does nothing when user was not previously suspended" do
      user = create(:user)
      ToggleHiddenUserInNotificationsJob.expects(:perform_later).never
      Hydro::EntitySerializer.expects(:user_suspended).never
      GlobalInstrumenter.expects(:instrument).never

      user.unsuspend("Test")
    end

    test "enqueues job to update follower and following counts" do
      user = create(:user, suspended_at: Time.now)
      CalculateFolloweringsCountJob.expects(:enqueue_once_per_interval).
        with(args: [user.id, true], interval: User::FollowDependency::FOLLOW_CALCULATION_INTERVAL_IN_SECONDS)
      user.unsuspend("Reasons")
    end

    test "unhides users when unsuspended" do
      user = create(:user)
      user.suspend "Reasons"
      user.unsuspend "Reasons"

      refute Newsies::HiddenUser.where(user_id: user.id).exists?
    end

    test "instruments unsuspend" do
      events = subscribe "user.unsuspend"
      user = create(:user)

      user.suspend("reasons")
      user.unsuspend("other reasons", actor: @staffer)

      expected_payload = {
        staff_actor: @staffer.login,
        staff_actor_id: @staffer.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
        reason: "other reasons",
      }

      assert event = events.pop, "a user.unsuspend event was expected"
      assert_equal "user.unsuspend", event.name
      assert_equal event.payload.merge(expected_payload), event.payload
    end
  end
end
