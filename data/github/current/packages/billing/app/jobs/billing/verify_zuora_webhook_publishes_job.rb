# typed: strict
# frozen_string_literal: true

module Billing
  class VerifyZuoraWebhookPublishesJob < ApplicationJob
    include GitHub::Memoizer

    queue_as :billing

    # Runs a one-off verification consumer that scans the Zuora webhook Hydro topic
    # from the beginning and logs whenever it observes a currently-pending webhook id.
    #
    # cutoff_timestamp - Integer seconds since epoch; consumption stops once messages
    #                   exceed this timestamp.
    sig { params(cutoff_timestamp: Integer).void }
    def perform(cutoff_timestamp:)
      consumer = nil
      processor = nil

      cutoff_time = Time.at(cutoff_timestamp)
      pending_ids = ::Billing::ZuoraWebhook.pending.not_sales_serve.ignoring_recent.pluck(:id)

      processor = ::GitHub::StreamProcessors::Billing::ZuoraWebhookVerificationProcessor.new(
        group_id: group_id,
        pending_webhook_ids: pending_ids,
      )

      GitHub.dogstats.increment("billing.verify_zuora_webhook_publishes_job", tags: ["status:started"])
      log_verification(
        "Starting Zuora webhook publish verification",
        cutoff_timestamp: cutoff_timestamp,
        extra: {
          "gh.billing.zuora.webhook.pending_count" => pending_ids.size,
        },
      )

      consumer = GitHub.hydro_consumer(
        processor.options.merge(
          automatically_mark_as_processed: false,
        )
      )

      reached_cutoff = T.let(false, T::Boolean)

      last_batch_received_at = T.let(Time.current, Time)
      Thread.new do # rubocop:disable GitHub/ThreadUse
        loop do
          if last_batch_received_at < 5.minutes.ago
            GitHub.dogstats.increment("billing.verify_zuora_webhook_publishes_job", tags: ["status:timeout"])
            log_verification(
              "No new Hydro messages received for 5 minutes; stopping Zuora webhook publish verification",
              cutoff_timestamp: cutoff_timestamp,
            )
            consumer&.close
            break
          end

          sleep 1
        end
      end

      consumer.open
      consumer.each_batch do |batch|
        last_batch_received_at = Time.current
        batch.each do |consumer_message|
          message_timestamp = consumer_message.timestamp
          if message_timestamp && Time.at(message_timestamp) > cutoff_time
            reached_cutoff = true
            break
          end

          processor.process_with_consumer(consumer_message, consumer)
          consumer.mark_message_as_processed(consumer_message)
        end

        break if reached_cutoff
      end
    rescue Hydro::Source::Error => e
      GitHub.dogstats.increment("billing.verify_zuora_webhook_publishes_job", tags: ["status:error"])
      log_verification(
        "Zuora webhook publish verification encountered a Hydro source error",
        cutoff_timestamp: cutoff_timestamp,
        exception: e,
      )
      raise
    ensure
      begin
        consumer&.close
      rescue StandardError
        # Ignore close errors; this is a debug-only job.
      end

      found_ids = processor&.found_webhook_ids&.to_a || []
      log_extra = {
        "gh.billing.zuora.webhook.verification.pending_count" => pending_ids.size,
        "gh.billing.zuora.webhook.verification.pending_ids" => pending_ids.join(","),
        "gh.billing.zuora.webhook.verification.found_count" => found_ids.size,
        "gh.billing.zuora.webhook.verification.found_ids" => found_ids.join(","),
        "gh.billing.zuora.webhook.verification.min_processed_id" => processor&.min_processed_webhook_id,
        "gh.billing.zuora.webhook.verification.max_processed_id" => processor&.max_processed_webhook_id,
        "gh.billing.zuora.webhook.verification.processed_webhook_count" => processor&.processed_webhook_count,
      }

      if found_ids.empty?
        GitHub.dogstats.increment("billing.verify_zuora_webhook_publishes_job", tags: ["status:finished_without_matches"])
        log_verification(
          "Completed Zuora webhook publish verification with nothing found",
          cutoff_timestamp: cutoff_timestamp,
          extra: log_extra,
        )
      else
        GitHub.dogstats.increment("billing.verify_zuora_webhook_publishes_job", tags: ["status:finished_with_matches"])
        log_verification(
          "Completed Zuora webhook publish verification",
          cutoff_timestamp: cutoff_timestamp,
          extra: log_extra,
        )
      end
    end

    private

    sig { returns(String) }
    memoize def group_id
      "github-#{Rails.env}-billing-zuora_webhook_verification-#{SecureRandom.hex(6)}"
    end

    sig do
      params(
        message: String,
        cutoff_timestamp: Integer,
        extra: T::Hash[String, T.untyped],
        exception: T.nilable(StandardError)
      ).void
    end
    def log_verification(message, cutoff_timestamp:, extra: {}, exception: nil)
      payload = {
        "code.namespace" => self.class.name,
        "code.function" => "perform",
        "gh.hydro.consumer.group_id" => group_id,
        "gh.billing.zuora.webhook.verification.cutoff_timestamp" => cutoff_timestamp,
      }.merge(extra)

      if exception
        GitHub.logger.error(message, payload.merge(exception: exception))
      else
        GitHub.logger.info(message, payload)
      end
    end
  end
end
