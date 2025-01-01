# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SponsorsListingZuoraSyncJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include JobTestHelper

  setup do
    FakeZuora.mock
  end

  fixtures do
    @listing = create(:sponsors_listing, :approved)
  end

  test "syncs listing to Zuora" do
    @listing.expects(:sync_to_zuora)

    SponsorsListingZuoraSyncJob.perform_now(@listing)
  end

  test "throttles database writes" do
    GitHub::Throttler::Null.any_instance.expects(:throttle)
      .times(3) # one_time, month, and year product UUID creation
      .yields
    SponsorsListingZuoraSyncJob.perform_now(@listing)
  end

  test "enqueues at most once for a given listing" do
    SponsorsListingZuoraSyncJob.perform_later(@listing)
    SponsorsListingZuoraSyncJob.perform_later(@listing)

    assert_enqueued_jobs 1, only: SponsorsListingZuoraSyncJob, queue: :zuora
  end

  test "retries on Zuorest error" do
    GitHub.zuorest_client.class.any_instance.stubs(:create_product)
      .with(anything)
      .raises(Zuorest::HttpError.new("bad zuora", {}))
    Failbot.expects(:report).never

    assert_enqueued_jobs(1, only: SponsorsListingZuoraSyncJob) do
      SponsorsListingZuoraSyncJob.perform_now(@listing)
    end

    assert_dogstats_increment 1, "active_job.retry"
  end

  test "retries using the ZuoraRateLimitHandler for too many requests error" do
    GitHub.zuorest_client.class.any_instance.stubs(:create_product)
      .with(anything)
      .raises(Zuorest::TooManyRequestsError.new("", {}, { "RateLimit-Reset" => "600" }))
    Failbot.expects(:report).never

    assert_enqueued_jobs(1, only: SponsorsListingZuoraSyncJob) do
      SponsorsListingZuoraSyncJob.perform_now(@listing)
    end

    assert_dogstats_increment 1, "billing.zuora_rate_limit_error", tags: ["class:sponsors_listing_zuora_sync_job"]
  end

  test "reports to Failbot after max retries" do
    GitHub.zuorest_client.class.any_instance.stubs(:create_product)
      .with(anything)
      .raises(Zuorest::HttpError.new("bad zuora", {}))
    SponsorsListingZuoraSyncJob.any_instance.stubs(:executions_for).returns(6)

    Failbot.expects(:report).once.with do |error|
      assert_equal Zuorest::HttpError, error.class
      assert_equal "HTTP bad zuora", error.message
    end

    assert_enqueued_jobs(0, only: SponsorsListingZuoraSyncJob) do
      SponsorsListingZuoraSyncJob.perform_now(@listing)
    end
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: SponsorsListingZuoraSyncJob, args: [@listing]
  end
end if GitHub.billing_enabled?
