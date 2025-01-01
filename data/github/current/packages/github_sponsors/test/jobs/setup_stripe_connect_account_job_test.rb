# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SetupStripeConnectAccountJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @sponsors_listing = create(:sponsors_listing, :with_stripe_account)
    @stripe_account = @sponsors_listing.active_stripe_connect_account
  end

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  test "uses the 'stripe' queue" do
    assert_enqueued_jobs(1, queue: "stripe") do
      SetupStripeConnectAccountJob.perform_later(@sponsors_listing, existing_stripe_account: @stripe_account)
    end
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: SetupStripeConnectAccountJob,
      args: [@sponsors_listing, { existing_stripe_account: @stripe_account }]
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: SetupStripeConnectAccountJob,
      args: [@sponsors_listing, { existing_stripe_account: @stripe_account }]
  end

  test "enqueues at most once with same arguments" do
    SetupStripeConnectAccountJob.perform_later(@sponsors_listing, existing_stripe_account: @stripe_account)
    SetupStripeConnectAccountJob.perform_later(@sponsors_listing, existing_stripe_account: @stripe_account)

    assert_enqueued_jobs 1, only: SetupStripeConnectAccountJob, queue: :stripe
  end

  test "fetches the account details" do
    Sponsors::SyncStripeAccountDetails.expects(:call).with(@stripe_account).once
    SetupStripeConnectAccountJob.perform_now(@sponsors_listing, existing_stripe_account: @stripe_account)
  end

  test "retries on Stripe::APIConnectionError" do
    ::Stripe::Account.stubs(:retrieve).raises(Stripe::APIConnectionError)

    assert_enqueued_with(
      job: SetupStripeConnectAccountJob,
      args: [@sponsors_listing, { existing_stripe_account: @stripe_account }],
    ) do
      SetupStripeConnectAccountJob.perform_now(@sponsors_listing, existing_stripe_account: @stripe_account)
    end
  end

  test "retries on Stripe::StripeError" do
    ::Stripe::Account.stubs(:retrieve).raises(Stripe::StripeError)

    assert_enqueued_with(
      job: SetupStripeConnectAccountJob,
      args: [@sponsors_listing, { existing_stripe_account: @stripe_account }],
    ) do
      SetupStripeConnectAccountJob.perform_now(@sponsors_listing, existing_stripe_account: @stripe_account)
    end
  end

  test "does not sync and retries when lock is in use for that Stripe account" do
    Sponsors::SyncStripeAccountDetails.expects(:call).never
    Stripe::Account.expects(:retrieve).never
    @sponsors_listing.sponsorable.enable_feature(:stripe_connect_account_lock)

    @stripe_account.with_lock do
      assert_enqueued_with(
        job: SetupStripeConnectAccountJob,
        args: [@sponsors_listing, { existing_stripe_account: @stripe_account }],
      ) do
        SetupStripeConnectAccountJob.perform_now(@sponsors_listing, existing_stripe_account: @stripe_account)
      end
    end
  end

  test "gives up after lock contention for too many attempts" do
    Sponsors::SyncStripeAccountDetails.expects(:call).never
    Stripe::Account.expects(:retrieve).never
    @sponsors_listing.sponsorable.enable_feature(:stripe_connect_account_lock)

    @stripe_account.with_lock do # lock in use
      ModifyStripeConnectAccountJob.stub_const(:LOCK_CONFLICT_ATTEMPTS, 1) do
        # should retry the job once
        assert_enqueued_with(
          job: SetupStripeConnectAccountJob,
          args: [@sponsors_listing, { existing_stripe_account: @stripe_account }],
        ) do
          SetupStripeConnectAccountJob.perform_now(@sponsors_listing, existing_stripe_account: @stripe_account)
        end

        # should not retry the job again because we've made the allowed number of attempts
        assert_no_enqueued_jobs(only: SetupStripeConnectAccountJob) do
          SetupStripeConnectAccountJob.perform_now(@sponsors_listing, existing_stripe_account: @stripe_account)
        end
      end
    end
  end

  test "reports lock contention" do
    @sponsors_listing.sponsorable.enable_feature(:stripe_connect_account_lock)

    perform_enqueued_jobs(only: [SetupStripeConnectAccountJob]) do
      @stripe_account.with_lock do # lock in use
        SetupStripeConnectAccountJob.perform_later(@sponsors_listing, existing_stripe_account: @stripe_account)
      end
    end

    failbot_report = Failbot.reports.last
    refute_nil failbot_report
    assert_equal "GitHub::Restraint::UnableToLock", Failbot.exception_classname_from_hash(failbot_report)
    assert_equal "github/github_sponsors", failbot_report["catalog_service"]
    assert_equal "SetupStripeConnectAccountJob", failbot_report["sensitive_context"]["active_job_class"]
    assert_equal @stripe_account.stripe_account_id, failbot_report["sensitive_context"]["stripe_account_id"]
  end
end
