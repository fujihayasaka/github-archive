# typed: strict
# frozen_string_literal: true

require "test_helper"

class ZuoraWebhookJobTest < GitHub::TestCase
  extend T::Sig

  include DogstatsTestHelpers

  test "uses the 'zuora' queue" do
    assert_enqueued_jobs 1, queue: "zuora" do
      ZuoraWebhookJob.perform_later(create(:zuora_webhook))
    end
  end

  test "does not attempt to perform a processed webhook" do
    webhook = create(:zuora_webhook, :processed)

    webhook.expects(:perform).never

    ZuoraWebhookJob.perform_now(webhook)
  end

  test "measures perform time" do
    webhook = travel_to(Time.new(2020, 1, 1, 12, 0, 0)) do
      create(
        :zuora_webhook,
        :invoice_posted,
        account_id: "2c92c0f961f9cf350161fde177ff0922",
        payload: { "AccountId" => "2c92c0f961f9cf350161fde177ff0922", "PaymentId" => "2c92c0fa6205232601622035ebfc5334" },
      )
    end

    travel_to(Time.new(2020, 1, 1, 12, 2, 0)) do
      ZuoraWebhookJob.perform_now(webhook)
    end

    assert_dogstats_distribution(1, "zuora.webhook_job.perform_time", tags: [
      "category:invoice_posted",
      "status:pending",
      "concurrency:#{ZuoraWebhookJob::DEFAULT_CONCURRENCY_LIMIT}",
    ])
  end

  test "allows modifying concurrency limit with KV" do
    webhook = travel_to(Time.new(2020, 1, 1, 12, 0, 0)) do
      create(
        :zuora_webhook,
        :invoice_posted,
        account_id: "2c92c0f961f9cf350161fde177ff0922",
        payload: { "AccountId" => "2c92c0f961f9cf350161fde177ff0922", "PaymentId" => "2c92c0fa6205232601622035ebfc5334" },
      )
    end

    ZuoraWebhookJob.set_concurrency(webhook_type: webhook.kind, concurrency: 1)

    travel_to(Time.new(2020, 1, 1, 12, 2, 0)) do
      ZuoraWebhookJob.perform_now(webhook)
    end

    assert_dogstats_distribution(1, "zuora.webhook_job.perform_time", tags: [
      "category:invoice_posted",
      "status:pending",
      "concurrency:1",
    ])
  end

  test "measures processing latency" do
    webhook = travel_to(Time.new(2020, 1, 1, 12, 0, 0)) do
      create(
        :zuora_webhook,
        :payment_processed,
        account_id: "2c92c0f961f9cf350161fde177ff0922",
        payload: { "AccountId" => "2c92c0f961f9cf350161fde177ff0922", "PaymentId" => "2c92c0fa6205232601622035ebfc5334" },
      )
    end

    travel_to(Time.new(2020, 1, 1, 12, 2, 0)) do
      ZuoraWebhookJob.perform_now(webhook)
    end

    assert_dogstats_timing(1, "zuora.webhook_latency")
    assert_dogstats_timing_value(120_000, "zuora.webhook_latency")
  end

  test "increments error metrics" do
    webhook = create(:zuora_webhook, :payment_processed)

    Billing::Zuora::Webhooks::PaymentProcessed.expects(:perform).raises(Billing::Zuora::WebhookError)

    Failbot.expects(:report).with do |error|
      assert_kind_of Billing::Zuora::WebhookError, error
    end

    ZuoraWebhookJob.perform_now(webhook)

    assert_dogstats_increment(1, "zuora.webhook_error", tags: [
      "category:payment_processed",
      "exception:billing-zuora-webhookerror",
    ])
  end

  test "it retries on Zuorest::TooManyRequestsError" do
    zuora_webhook = create(
      :zuora_webhook,
      :payment_processed,
      account_id: "2c92c0f961f9cf350161fde177ff0922",
      payload: { "AccountId" => "2c92c0f961f9cf350161fde177ff0922", "PaymentId" => "2c92c0fa6205232601622035ebfc5334" },
    )

    error = Zuorest::TooManyRequestsError.new("", {}, { "RateLimit-Reset" => "600" })
    Billing::ZuoraWebhook.any_instance.expects(:perform).raises(error)

    ZuoraWebhookJob.any_instance.expects(:retry_job)

    ZuoraWebhookJob.perform_now(zuora_webhook)
    assert_dogstats_increment(1, "billing.zuora_rate_limit_error", tags: [
      "class:zuora_webhook_job"
    ])
  end

  test "retries GitHub::Restraint::LockError and reports on exhaustion" do
    zuora_webhook = create(
      :zuora_webhook,
      :payment_processed,
      account_id: "2c92c0f961f9cf350161fde177ff0922",
      payload: { "AccountId" => "2c92c0f961f9cf350161fde177ff0922", "PaymentId" => "2c92c0fa6205232601622035ebfc5334" },
    )

    error = GitHub::Restraint::UnableToLock
    Billing::ZuoraWebhook.any_instance.stubs(:perform).raises(error, "The internet is broken")

    perform_enqueued_jobs(only: ZuoraWebhookJob) do
      ZuoraWebhookJob.perform_later(zuora_webhook)
    end

    expected_tags = [
      "class:zuora_webhook_job",
      "queue:zuora",
      "error:#{error.name.to_s.underscore}",
    ]

    # Retries
    increments = GitHub.dogstats.increments("active_job.retry")
    assert_equal 19, increments.length, "Expected job to be retried on #{error.name}, but it wasn't"

    stats_tags = increments.first.args[2][:tags]

    # Take the intersection to ensure that all of our expected, desired
    # tags are present in the actual, while ignoring any "extra" tags
    # added by the implementation of underlying technologies.
    assert_equal 3, (expected_tags & stats_tags).length,
      "Expected job to be retried on #{error.name}, but it wasn't"

    assert_equal 1, GitHub.dogstats.increments("zuora.webhook_error", tags: [
      "category:#{zuora_webhook.kind}",
      "exception:#{error.name.to_s.parameterize}",
    ]).length, "Expected the retry to report on exhaustion, but it didn't"
  end

  test "retries errors that make sense to be retried on" do
    zuora_webhook = create(
      :zuora_webhook,
      :payment_processed,
      account_id: "2c92c0f961f9cf350161fde177ff0922", payload: { "AccountId" => "2c92c0f961f9cf350161fde177ff0922", "PaymentId" => "2c92c0fa6205232601622035ebfc5334" },
    )

    [
      ::Billing::Zuora::LockCompetitionError,
      ::Billing::ZuoraWebhook::RetryableError,
      ActiveRecord::RecordNotUnique,
      ActiveRecord::StatementInvalid,
      Audit::EventForwarder::SubscribeError,
      Braintree::UnexpectedError,
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::ETIMEDOUT,
      Faraday::ConnectionFailed,
      Faraday::ParsingError,
      Faraday::SSLError,
      Faraday::TimeoutError,
      Net::OpenTimeout,
      Redis::TimeoutError,
      Stripe::APIError,
      Zuorest::HttpError,
    ].each do |error|
      if error != Zuorest::HttpError
        Billing::ZuoraWebhook.any_instance.expects(:perform).raises(error, "The internet is broken")
      else
        Billing::ZuoraWebhook.any_instance.expects(:perform).raises(error.new("The internet is broken", nil))
      end
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      ZuoraWebhookJob.perform_now(zuora_webhook)

      expected_tags = [
        "class:zuora_webhook_job",
        "queue:zuora",
        "error:#{error.name.to_s.underscore}",
      ]

      increments = GitHub.dogstats.increments("active_job.retry")
      assert_equal 1, increments.length, "Expected job to be retried on #{error.name}, but it wasn't"

      stats_tags = increments.first.args[2][:tags]

      # Take the intersection to ensure that all of our expected, desired
      # tags are present in the actual, while ignoring any "extra" tags
      # added by the implementation of underlying technologies.
      assert_equal 3, (expected_tags & stats_tags).length,
        "Expected job to be retried on #{error.name}, but it wasn't"

      assert_equal 0, GitHub.dogstats.increments("zuora.webhook_error", tags: [
        "category:#{zuora_webhook.kind}",
        "exception:#{error.name.to_s.parameterize}",
      ]).length, "Expected the retry errors to prevent this from updating Datadog, but it didn't"
    end
  end
end if GitHub.billing_enabled?
