# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ConfigureStripeAccountJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @stripe_account = create(:stripe_connect_account)
    @listing = @stripe_account.sponsors_listing
  end

  setup do
    skip unless GitHub.sponsors_enabled?
    @automatic_response = Stripe::Account.construct_from(
      id: @stripe_account.stripe_account_id,
      settings: {
        payouts: {
          schedule: {
            delay_days: 2,
            interval: "monthly",
            monthly_anchor: 22,
          },
        },
      },
    )
    @manual_response = Stripe::Account.construct_from(
      id: @stripe_account.stripe_account_id,
      settings: {
        payouts: {
          schedule: {
            delay_days: 2,
            interval: "manual",
          },
        },
      },
    )
  end

  test "uses the 'stripe' queue" do
    assert_enqueued_jobs(1, queue: "stripe") do
      ConfigureStripeAccountJob.perform_later(@stripe_account)
    end
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: ConfigureStripeAccountJob, args: [@stripe_account]
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: ConfigureStripeAccountJob, args: [@stripe_account]
  end

  test "enqueues at most once with same arguments" do
    ConfigureStripeAccountJob.perform_later(@stripe_account)
    ConfigureStripeAccountJob.perform_later(@stripe_account)

    assert_enqueued_jobs 1, only: ConfigureStripeAccountJob, queue: :stripe
  end

  context "payout schedule" do
    test "sets payouts to manual" do
      Stripe::Account.stubs(:update).returns(@manual_response)

      ConfigureStripeAccountJob.perform_now(@stripe_account)
      assert_predicate @stripe_account, :automated_payouts_disabled?
    end

    test "sets payouts to monthly" do
      Stripe::Account.stubs(:update).returns(@automatic_response)

      ConfigureStripeAccountJob.perform_now(@stripe_account, freeze_payouts: true)
      refute_predicate @stripe_account, :automated_payouts_disabled?
    end

    test "reports to Failbot on Stripe::OAuth::InvalidGrantError" do
      error = Stripe::OAuth::InvalidGrantError.new("one", "two")
      Stripe::Account.stubs(:update).raises(error)
      Failbot.expects(:report)
        .once
        .with(
          instance_of(Stripe::OAuth::InvalidGrantError),
          stripe_connect_account_id: @stripe_account.id,
          stripe_account_id: @stripe_account.stripe_account_id,
          actor_id: nil,
          freeze_payouts: true,
          app: "github-external-request",
        )

      ConfigureStripeAccountJob.perform_now(@stripe_account, freeze_payouts: true)
    end

    test "reports to Failbot on Stripe::InvalidRequestError" do
      error = Stripe::InvalidRequestError.new('The payout interval "monthly" is not available for merchants in BR.',
        "param")
      Stripe::Account.stubs(:update).raises(error)
      actor = create(:user)
      Failbot.expects(:report).once.with(instance_of(Stripe::InvalidRequestError),
        stripe_connect_account_id: @stripe_account.id,
        stripe_account_id: @stripe_account.stripe_account_id,
        actor_id: actor.id,
        freeze_payouts: false,
        app: "github-external-request",
      )

      ConfigureStripeAccountJob.perform_now(@stripe_account, freeze_payouts: false, actor: actor)
    end

    test "retries on Stripe::APIConnectionError" do
      Stripe::Account.stubs(:update).raises(Stripe::APIConnectionError)
      ConfigureStripeAccountJob.any_instance.expects(:retry_job).once
      ConfigureStripeAccountJob.perform_now(@stripe_account, freeze_payouts: true)
    end

    test "retries on Stripe::StripeError" do
      Stripe::Account.stubs(:update).raises(Stripe::StripeError)
      ConfigureStripeAccountJob.any_instance.expects(:retry_job).once
      ConfigureStripeAccountJob.perform_now(@stripe_account, freeze_payouts: true)
    end

    test "retries on Sponsors::ConfigureStripeAccount::UpdatePayoutsFailedError" do
      error = Sponsors::ConfigureStripeAccount::UpdatePayoutsFailedError
      Stripe::Account.stubs(:update).raises(error)
      ConfigureStripeAccountJob.any_instance.expects(:retry_job).once
      ConfigureStripeAccountJob.perform_now(@stripe_account, freeze_payouts: true)
    end

    test "passes through reason to Sponsors::ConfigureStripeAccount" do
      actor = create(:user)
      reason = "We gotta do it"
      Sponsors::ConfigureStripeAccount.expects(:call).once.with(account: @stripe_account, freeze_payouts: true,
        actor: actor, reason: reason)

      ConfigureStripeAccountJob.perform_now(@stripe_account, freeze_payouts: true, actor: actor, reason: reason)
    end

    test "reports to dogstats on Stripe::PermissionError" do
      GitHub.dogstats.expects(:increment).at_least_once
      GitHub.dogstats.expects(:increment)
        .with("stripe.permission_error", tags: ["action:toggle_payouts"])
        .at_least_once
      Stripe::Account.stubs(:update).raises(Stripe::PermissionError, "unauthorized")
      ConfigureStripeAccountJob.perform_now(@stripe_account, freeze_payouts: true)
    end
  end

  test "does not sync and retries when lock is in use for that Stripe account" do
    enable_feature_flag(:stripe_connect_account_lock, @listing.sponsorable)
    Sponsors::ConfigureStripeAccount.expects(:call).never

    @stripe_account.with_lock do
      assert_enqueued_with(
        job: ConfigureStripeAccountJob,
        args: [@stripe_account, { freeze_payouts: true }],
      ) do
        ConfigureStripeAccountJob.perform_now(@stripe_account, freeze_payouts: true)
      end
    end
  end

  test "gives up after lock contention for too many attempts" do
    enable_feature_flag(:stripe_connect_account_lock, @listing.sponsorable)
    Sponsors::ConfigureStripeAccount.expects(:call).never

    @stripe_account.with_lock do # lock in use
      ModifyStripeConnectAccountJob.stub_const(:LOCK_CONFLICT_ATTEMPTS, 1) do
        # should retry the job once
        assert_enqueued_with(
          job: ConfigureStripeAccountJob,
          args: [@stripe_account, { freeze_payouts: true }],
        ) do
          ConfigureStripeAccountJob.perform_now(@stripe_account, freeze_payouts: true)
        end

        # should not retry the job again because we've made the allowed number of attempts
        assert_no_enqueued_jobs(only: ConfigureStripeAccountJob) do
          ConfigureStripeAccountJob.perform_now(@stripe_account, freeze_payouts: true)
        end
      end
    end
  end

  test "reports lock contention" do
    enable_feature_flag(:stripe_connect_account_lock, @listing.sponsorable)

    perform_enqueued_jobs(only: [ConfigureStripeAccountJob]) do
      @stripe_account.with_lock do # lock in use
        ConfigureStripeAccountJob.perform_later(@stripe_account, freeze_payouts: true)
      end
    end

    failbot_report = Failbot.reports.last
    refute_nil failbot_report
    assert_equal "GitHub::Restraint::UnableToLock", Failbot.exception_classname_from_hash(failbot_report)
    assert_equal "github/github_sponsors", failbot_report["catalog_service"]
    assert_equal "ConfigureStripeAccountJob", failbot_report["sensitive_context"]["active_job_class"]
    assert_equal @stripe_account.stripe_account_id, failbot_report["sensitive_context"]["stripe_account_id"]
  end
end
