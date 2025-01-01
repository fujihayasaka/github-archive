# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::CheckVssSubscriptionEventFailuresJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  setup do
    @now = Time.new(2020, 8, 10, 19, 0, 0)
  end

  test "uses the 'licensing' queue" do
    assert_enqueued_jobs(1, queue: "licensing") do
      Licensing::CheckVssSubscriptionEventFailuresJob.perform_later
    end
  end

  test "reports VssSubscriptionEvent with failed status" do
    # To exclude job retries, only includes results that are at least 10 mins old
    travel_to(@now - 11.minutes) do
      event = create(:licensing_vss_subscription_event)
      event.failed!
    end

    travel_to(@now) do
      Licensing::CheckVssSubscriptionEventFailuresJob.perform_now
    end

    assert_dogstats_gauge_value 1, "licensing.vss_subscription_event_failures.count"
    assert_dogstats_gauge_value 11.minutes.to_i * 1000, "licensing.vss_subscription_event_failures.max_age"
  end

  test "does not report subscription event if processed" do
    travel_to(@now - 11.minutes) do
      event = create(:licensing_vss_subscription_event)
      event.processed!
    end

    travel_to(@now) do
      Licensing::CheckVssSubscriptionEventFailuresJob.perform_now
    end

    assert_dogstats_gauge_value 0, "licensing.vss_subscription_event_failures.count"
    assert_dogstats_gauge 0, "licensing.vss_subscription_event_failures.max_age"
  end
end if GitHub.billing_enabled?
