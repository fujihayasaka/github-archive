# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::CheckVssSubscriptionUnprocessedEventsJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  test "reports VssSubscriptionEvents that are older than 5 minutes and still have the unprocessed status" do
    freeze_time do
      _processed_event = create(:licensing_vss_subscription_event, created_at: 10.minutes.ago, status: :processed)
      _unprocessed_event = create(:licensing_vss_subscription_event, created_at: 6.minutes.ago)
      _new_unprocessed_event = create(:licensing_vss_subscription_event, created_at: 4.minutes.ago)
      _recently_processed_events = create_list(:licensing_vss_subscription_event, 10, created_at: 1.minute.ago, status: :processed)

      Licensing::CheckVssSubscriptionUnprocessedEventsJob.perform_now

      assert_dogstats_gauge_value 1, "licensing.vss_subscription_unprocessed_events.count"
      assert_dogstats_gauge_value 6.minutes.to_i * 1000, "licensing.vss_subscription_unprocessed_events.max_age"
    end
  end
end if GitHub.billing_enabled?
