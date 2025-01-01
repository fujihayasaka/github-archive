# typed: true
# frozen_string_literal: true

require "test_helper"

class Stafftools::VssSubscriptionEvents::EventComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  setup do
    travel_to Time.parse("2021-02-04T12:34:45Z") do
      @event = create(
        :licensing_vss_subscription_event,
        :under_investigation,
        :assignment,
        subscription_id: "some-sub-id",
        email: "foo@example.com"
      )
    end
  end

  test "renders the details correctly" do
    render_inline(Stafftools::VssSubscriptionEvents::EventComponent.new(event: @event))

    assert_test_selector("id", text: @event.id)
    assert_test_selector("status", text: "Under Investigation")
    assert_test_selector("operation", text: "Assign")
    assert_test_selector("created-at", text: "2021-02-04")
  end
end if GitHub.billing_enabled?
