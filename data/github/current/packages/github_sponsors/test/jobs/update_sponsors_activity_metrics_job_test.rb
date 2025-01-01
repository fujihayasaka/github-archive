# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class UpdateSponsorsActivityMetricsJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @now = Time.now.freeze
    @today = @now.to_date.freeze
    @listing = create(:sponsors_listing, :approved, :with_tier)
    sponsorship = create(:sponsorship, tier: @listing.default_tier)
    @subscription_item = sponsorship.subscription_item
  end

  test "creates a subscription value metric for an approved sponsors listing" do
    sponsorable = @listing.sponsorable

    assert_predicate sponsorable.sponsors_activity_metrics, :empty?

    assert_difference "SponsorsActivityMetric.count", 1 do
      Timecop.freeze(@now) { UpdateSponsorsActivityMetricsJob.perform_now }
    end

    assert metric = sponsorable.sponsors_activity_metrics.subscription_value.last
    assert_equal @listing.default_tier.monthly_price_in_cents, metric.value
    assert_equal @today, metric.recorded_on
  end

  test "updates a subscription value metric for an approved sponsors listing" do
    sponsorable = @listing.sponsorable
    metric = sponsorable.sponsors_activity_metrics.subscription_value.create!(value: 42, recorded_on: @today)

    assert_no_difference "SponsorsActivityMetric.count" do
      Timecop.freeze(@now) { UpdateSponsorsActivityMetricsJob.perform_now }
    end

    assert_equal @listing.default_tier.monthly_price_in_cents, metric.reload.value
    assert_equal @today, metric.recorded_on
  end

  test "does not create a subscription value metric for an unapproved sponsors listing" do
    listing = create(:sponsors_listing, :draft)
    sponsorable = listing.sponsorable

    assert_predicate sponsorable.sponsors_activity_metrics, :empty?

    Timecop.freeze(@now) { UpdateSponsorsActivityMetricsJob.perform_now }

    assert_predicate sponsorable.sponsors_activity_metrics, :empty?
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: UpdateSponsorsActivityMetricsJob
  end
end
