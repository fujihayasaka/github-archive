# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SyncSponsorsStripeAccountJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @sponsors_listing = create(:sponsors_listing)
    @stripe_account = create(:stripe_connect_account, sponsors_listing: @sponsors_listing)
  end

  setup do
    skip unless GitHub.sponsors_enabled?
    Sponsors::SyncStripeAccountDetails.stubs(:call)
  end

  test "retries on a dirty exit" do
    assert_retry_on_dirty_exit job: SyncSponsorsStripeAccountJob, args: [@stripe_account]
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: SyncSponsorsStripeAccountJob, args: [@stripe_account]
  end

  SyncSponsorsStripeAccountJob::RETRYABLE_ERRORS.each do |exception_class|
    test "retries on #{exception_class}" do
      Sponsors::SyncStripeAccountDetails.stubs(:call).raises(exception_class)
      SyncSponsorsStripeAccountJob.any_instance.expects(:retry_job).once
      SyncSponsorsStripeAccountJob.perform_now(@stripe_account)
    end if GitHub.sponsors_enabled?
  end

  test "has a lock based on the given Stripe account" do
    job1 = SyncSponsorsStripeAccountJob.new(@stripe_account)
    job2 = SyncSponsorsStripeAccountJob.new(@stripe_account)
    assert_equal job1.lock_key, job2.lock_key

    other_stripe_account = create(:stripe_connect_account)
    job3 = SyncSponsorsStripeAccountJob.new(other_stripe_account)
    refute_equal job1.lock_key, job3.lock_key
    refute_equal job2.lock_key, job3.lock_key
  end

  test "only enqueues one sync job for a given Stripe account in a time period" do
    now = Time.now

    # Repeated calls to enqueue a job for one account at the same time should only result in a single job being
    # enqueued:
    travel_to(now) do
      assert_enqueued_jobs 1 do
        SyncSponsorsStripeAccountJob.perform_later(@stripe_account)
        SyncSponsorsStripeAccountJob.perform_later(@stripe_account)
      end
    end

    # Should be able to enqueue a job for the same account again, once enough time has passed:
    travel_to(now + (SyncSponsorsStripeAccountJob::TIMEOUT_IN_HOURS + 1).hours) do
      assert_enqueued_jobs 1 do
        SyncSponsorsStripeAccountJob.perform_later(@stripe_account)
      end
    end
  end

  if GitHub.sponsors_enabled?
    test "fetches Stripe account details for specified account" do
      Sponsors::SyncStripeAccountDetails.expects(:call).with(@stripe_account).once
      SyncSponsorsStripeAccountJob.perform_now(@stripe_account)
    end
  else
    test "no-op when Sponsors is disabled" do
      Sponsors::SyncStripeAccountDetails.expects(:call).never
      SyncSponsorsStripeAccountJob.perform_now(@stripe_account)
    end
  end

  test "no-op when Sponsors listing no longer exists" do
    @sponsors_listing.delete
    Sponsors::SyncStripeAccountDetails.expects(:call).never
    SyncSponsorsStripeAccountJob.perform_now(@stripe_account)
  end

  test "does not sync and retries when lock is in use for that Stripe account" do
    Sponsors::SyncStripeAccountDetails.expects(:call).never
    @sponsors_listing.sponsorable.enable_feature(:stripe_connect_account_lock)

    @stripe_account.with_lock do
      assert_enqueued_with(job: SyncSponsorsStripeAccountJob, args: [@stripe_account]) do
        SyncSponsorsStripeAccountJob.perform_now(@stripe_account)
      end
    end
  end

  test "gives up after lock contention for too many attempts" do
    Sponsors::SyncStripeAccountDetails.expects(:call).never
    @sponsors_listing.sponsorable.enable_feature(:stripe_connect_account_lock)

    @stripe_account.with_lock do # lock in use
      ModifyStripeConnectAccountJob.stub_const(:LOCK_CONFLICT_ATTEMPTS, 1) do
        # should retry the job once
        assert_enqueued_with(job: SyncSponsorsStripeAccountJob, args: [@stripe_account]) do
          SyncSponsorsStripeAccountJob.perform_now(@stripe_account)
        end

        # should not retry the job again because we've made the allowed number of attempts
        assert_no_enqueued_jobs(only: SyncSponsorsStripeAccountJob) do
          SyncSponsorsStripeAccountJob.perform_now(@stripe_account)
        end
      end
    end
  end

  test "reports lock contention" do
    @sponsors_listing.sponsorable.enable_feature(:stripe_connect_account_lock)

    perform_enqueued_jobs(only: [SyncSponsorsStripeAccountJob]) do
      @stripe_account.with_lock do # lock in use
        SyncSponsorsStripeAccountJob.perform_later(@stripe_account)
      end
    end

    failbot_report = Failbot.reports.last
    refute_nil failbot_report
    assert_equal "GitHub::Restraint::UnableToLock", Failbot.exception_classname_from_hash(failbot_report)
    assert_equal "github/github_sponsors", failbot_report["catalog_service"]
    assert_equal "SyncSponsorsStripeAccountJob", failbot_report["sensitive_context"]["active_job_class"]
    assert_equal @stripe_account.stripe_account_id, failbot_report["sensitive_context"]["stripe_account_id"]
  end
end
