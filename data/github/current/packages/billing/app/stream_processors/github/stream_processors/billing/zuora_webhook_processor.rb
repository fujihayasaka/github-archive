# typed: strict
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Billing
      class ZuoraWebhookProcessor < SingleMessageProcessor
        # We need a write connection to avoid ActiveRecord::RecordNotFound errors when retrieving the webhook.
        default_to_write_connection!

        include TransientErrorResiliency

        # In addition to TransientErrorResiliency, we define an additional set of errors we want to retry on
        set_callback :message, :around, :retry_on_transient_errors

        TRANSIENT_ERRORS_TO_RETRY_ON = T.let(::Billing::ZuoraWebhook::RETRYABLE_ERRORS + [
          Zuorest::TooManyRequestsError,
        ], T::Array[T.class_of(StandardError)])

        DEFAULT_GROUP_ID = T.let("github-#{Rails.env}-billing-zuora_webhook_processor", String)
        DEFAULT_SUBSCRIBE_TO = /github\.billing\.v0\.ZuoraWebhook\Z/

        # This is the timeout used for determining if a given Kafka consumer has
        # failed or quit due to e.g. a deploy. Setting it to a lower value is NOT
        # recommended if your Hydro processor interacts with the database, since
        # Freno may wait up to 30 seconds when throttling writes. Processors that
        # do not interact with a database may lower this value to allow faster
        # consumer group rebalancing during deploys and processor failures.
        #
        # See https://kafka.apache.org/documentation/#session.timeout.ms
        options[:session_timeout] = 300.seconds

        # This value must be greater than "session_timeout"
        #
        # See https://github.com/zendesk/ruby-kafka#understanding-timeouts
        options[:socket_timeout] = 305.seconds

        # When the processor starts consuming from a partition for the first time and has no committed offsets,
        # `start_from_beginning` determines if should start from the beginning of the log (i.e. the oldest available messages)
        # or the end of the log (i.e. the newest available messages).
        #
        # This is the equivalent of the java client `auto.offset.reset` consumer config.
        # See: https://kafka.apache.org/documentation/#consumerconfigs_auto.offset.reset
        options[:start_from_beginning] = false

        # Other options you may want to set...
        #
        # This will cause the Kafka consumer to wait until there is at least a
        # given number of bytes available to fetch; but the consumer will wait
        # no longer than "max_wait_time" (described below). This allows the
        # processor to wait for a large enough batch of data. The default is
        # 1 byte, meaning data will be fetched as soon as it's available. Value
        # below is for example purposes only and not a recommendation; the default
        # value of 1 should be suitable for most cases.
        # See https://kafka.apache.org/documentation/#fetch.min.bytes
        # options[:min_bytes] = 1.kilobyte
        #
        # This is the maximum amount of time the Kafka consumer will wait to
        # fetch data. The default is 500ms (0.5.seconds). Value below is for
        # example purposes only and not a recommendation; the default value of
        # 500ms should be suitable for most cases.
        # options[:max_wait_time] = 1.second
        #
        # This is the maximum amount of data that will be fetched at a time. This
        # value is specified in bytes, so the number of distinct Hydro messages
        # fetched depends on the size of those messages. The default is 1MB. You
        # may want to consider lowering this if processing each batch of messages
        # is taking more than 60 seconds in order to ensure that your processor
        # shuts down in a timely manner during deploys.
        # See https://kafka.apache.org/documentation/#max.partition.fetch.bytes
        # options[:max_bytes_per_partition] = 100.kilobytes

        # Public: Configure the Hydro processor
        sig { params(kwargs: T.untyped).void }
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
          GitHub.zuorest_client = GitHub.zuorest_background_worker_client
          Zuorest::Model::Base.zuora_rest_client = GitHub.zuorest_client
          Failbot.push(zuorest_background_worker_client: true)
          self.transient_error_max_retries = 10
        end

        sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
        def process_message(message)
          zuora_webhook = ::Billing::ZuoraWebhook.find(message.value[:webhook_id])

          Failbot.push(
            "gh.billing.zuora.webhook_type": zuora_webhook.kind,
            "gh.billing.zuora.webhook_id": zuora_webhook.id
          )
          tags = [
            "category:#{zuora_webhook.kind}",
            "status:#{zuora_webhook.status}",
            "via_processor:true",
          ]
          GitHub.dogstats.distribution_time("zuora.webhook_job.perform_time", tags: tags) do
            zuora_webhook.perform
          end
        end

        private

        sig { params(blk: T.proc.void).void }
        def retry_on_transient_errors(&blk)
          attempts = 0

          begin
            yield
          rescue => error # rubocop:disable Lint/RescueException
            if attempts < transient_error_max_retries && TRANSIENT_ERRORS_TO_RETRY_ON.any? { |error_class| error.is_a?(error_class) }
              attempts += 1
              stats.increment("github.stream_processors.transient_error.retry", tags: default_stats_tags + ["attempts:#{attempts}", "error:#{error.class}"])
              log_retry(error, attempts)
              sleep(attempts)
              retry
            else
              raise
            end
          end
        end

        sig { params(error: StandardError, attempts: Integer).void }
        def log_retry(error, attempts)
          context = current_error_context || {}
          context = context.merge(
            "code.namespace" => self.class.name,
            "code.function" => "retry_on_transient_errors",
            "gh.processor.name" => self.class.name,
            "gh.catalog_service" => logical_service,
            "gh.processor.retry.attempts" => attempts,
            "exception.stacktrace" => error.backtrace.to_s
          )
          GitHub.logger.error(error, context)
        end
      end
    end
  end
end
