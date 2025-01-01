# frozen_string_literal: true

require "test_helper"

class ProcessAdvisoryAlertingEventJobTest < ActiveJob::TestCase
  test "calls AdvisoryAlertingEvent.create_or_update_from_hydro with correct data" do
    message = {
      ghsa_id: GHSAIDGenerator.generate_ghsa_id,
      alerting_event_id: 100,
      processed_at: 5.minutes.ago,
      finished_at: Time.zone.now,
      notification_count: 1,
      alert_count: 2,
    }
    AdvisoryAlertingEvent.expects(:create_or_update_from_hydro).with(message).once

    ProcessAdvisoryAlertingEventJob.new.perform(message)
  end
end
