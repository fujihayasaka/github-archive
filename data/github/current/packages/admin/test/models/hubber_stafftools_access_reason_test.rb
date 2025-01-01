# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class HubberStafftoolsAccessReasonTest < GitHub::TestCase
    test "sets and instruments the reason" do
      staffer1 = create(:staff_admin_user)
      staffer2 = create(:staff_admin_user)
      expiration_time = 1.hour.from_now
      events = subscribe("staff.hubber_access_reason_provided")
      expected_payload = {
        staff_actor: staffer1.login,
        staff_actor_id: staffer1.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
        viewing_reason: "testing",
        user: staffer2.login,
        user_id: staffer2.id,
      }

      staffer1.set_hubber_access_reason(staffer2, "testing")
      assert staffer1.hubber_access_reason_provided?(staffer2)

      assert event = events.pop
      assert_equal expected_payload, event.payload
    end
  end
end
