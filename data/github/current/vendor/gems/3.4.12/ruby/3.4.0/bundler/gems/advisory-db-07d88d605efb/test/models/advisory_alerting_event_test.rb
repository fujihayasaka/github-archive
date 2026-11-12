# frozen_string_literal: true

require "test_helper"

class AdvisoryAlertingEventTest < ActiveSupport::TestCase
  test "updates an existing alerting event" do
    alerting_event = create(:processed_alerting_event)
    message = {
      ghsa_id: alerting_event.ghsa_id,
      alerting_event_id: alerting_event.alerting_event_id,
      processed_at: Google::Protobuf::Timestamp.from_time(alerting_event.processed_at).to_h,
      finished_at: Google::Protobuf::Timestamp.from_time(Time.zone.now).to_h,
      notification_count: 1,
      alert_count: 1,
    }

    assert_no_difference -> { AdvisoryAlertingEvent.count } do
      AdvisoryAlertingEvent.create_or_update_from_hydro(message)
    end

    alerting_event.reload
    assert_equal 1, alerting_event.notification_count
    assert_equal 1, alerting_event.alert_count
    refute_nil alerting_event.finished_at
  end

  test "creates a new alerting event" do
    advisory = create(:advisory)

    message = {
      ghsa_id: advisory.ghsa_id,
      alerting_event_id: 1,
      processed_at: Google::Protobuf::Timestamp.from_time(5.minutes.ago).to_h,
      finished_at: nil,
      notification_count: 0,
      alert_count: 0,
    }

    assert_difference -> { AdvisoryAlertingEvent.count }, 1 do
      AdvisoryAlertingEvent.create_or_update_from_hydro(message)
    end
  end

  test "creates a new alerting event when GHSA ID is the same but alerting event ID differs" do
    alerting_event = create(:finished_alerting_event)
    message = {
      ghsa_id: alerting_event.ghsa_id,
      alerting_event_id: 100,
      processed_at: Google::Protobuf::Timestamp.from_time(alerting_event.processed_at).to_h,
      finished_at: nil,
      notification_count: 0,
      alert_count: 0,
    }

    assert_difference -> { AdvisoryAlertingEvent.count }, 1 do
      AdvisoryAlertingEvent.create_or_update_from_hydro(message)
    end
  end
end
