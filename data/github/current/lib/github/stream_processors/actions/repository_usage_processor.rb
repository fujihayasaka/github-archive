# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Actions
      class RepositoryUsageProcessor < Hydro::Processor
        include GitHub::ServiceMapping

        DEFAULT_GROUP_ID = "actions_repository_usage_processor"
        DEFAULT_SUBSCRIBE_TO = /github\.actions\.v0\.ResolveActionRequest\Z/
        STATS_NAMESPACE = "actions_repository_usage_processor"

        options[:session_timeout] = 60.seconds
        options[:socket_timeout] = 65.seconds

        # We want to ensure that messages are only committed after the entire batch has been processed
        options[:automatically_mark_as_processed] = true

        # When connecting for the first time, should we consume from the start
        # of the topic or only process new messages as they arrive
        # This only applies on the first ever connection for this consumergroup
        options[:start_from_beginning] = false

        # This is the maximum amount of data that will be fetched at a time. This
        # value is specified in bytes, so the number of distinct Hydro messages
        # fetched depends on the size of those messages. The default is 1MB. You
        # may want to consider lowering this if processing each batch of messages
        # is taking more than 60 seconds in order to ensure that your processor
        # shuts down in a timely manner during deploys.
        # See https://kafka.apache.org/documentation/#max.partition.fetch.bytes
        # Currently, the average message size for ResolveActionRequest is ~560 bytes
        options[:max_bytes_per_partition] = 256.kilobytes

        def batching?
          true
        end

        def initialize
          options[:group_id] = DEFAULT_GROUP_ID
          options[:subscribe_to] = DEFAULT_SUBSCRIBE_TO

          Failbot.push(
            stream_processor: self.class.name&.underscore,
            group_id: options[:group_id],
            subscribe_to: options[:subscribe_to].to_s,
          )
        end

        def process_with_consumer(batch, consumer) # rubocop:todo GitHub/DoNotOverrideProccessWithConsumerMethod
          class_name = self.class.name&.underscore
          GitHub.context.push(db_call_source_datadog_tags: [
            "source_type:stream_processor",
            "stream_processor:#{class_name}",
            "source:stream_processor-#{class_name}",
          ])

          reset_usage_counts
          GitHub.dogstats.increment("#{STATS_NAMESPACE}.received_batch")

          GitHub.dogstats.distribution_time("#{STATS_NAMESPACE}.process_batch.dist.time") do
            process_batch(batch)
          end

          GitHub.dogstats.count("#{STATS_NAMESPACE}.repository_count", @usage_counts.length)
          GitHub.dogstats.count("#{STATS_NAMESPACE}.batch_length", batch.length)

          GitHub.dogstats.distribution_time("#{STATS_NAMESPACE}.persist_and_flush.dist.time") do
            persist_and_flush
          end
        ensure
          GitHub.context.pop_key(:db_call_source_datadog_tags)
        end

        private

        def process_batch(batch)
          emit_tenant_context_metrics

          batch.each do |message|
            next if skip_message?(message)
            latency_ms = (Time.now.to_f - message.timestamp.to_f) * 1_000

            GitHub.dogstats.increment("#{STATS_NAMESPACE}.messages", tags: ["partition:#{message.partition}"])
            GitHub.dogstats.distribution("#{STATS_NAMESPACE}.latency", latency_ms.to_i, tags: ["partition:#{message.partition}"])

            repository_id = message.value.dig(:resolved_repository, :id)
            increment_repository_usage(repository_id)
          end
        end

        def persist_and_flush
          @usage_counts.each do |repository_id, batch_count|
            ::Actions::RepositoryUsage.increment_usage_for(repository_id, time: Time.now, count: batch_count)
          end
        end

        def reset_usage_counts
          @usage_counts = Hash.new(0)
        end

        def skip_message?(message)
          reason = skip_reason(message)

          return false unless reason.present?

          GitHub.dogstats.increment("#{STATS_NAMESPACE}.message_skipped", tags: [
            "partition:#{message.partition}",
            "reason:#{reason}"
          ])

          true
        end

        def skip_reason(message)
          return "ghes_not_supported" if GitHub.enterprise?

          repository_id = message.value.dig(:resolved_repository, :id)
          return "blank_repository_id" if repository_id.nil? || repository_id.to_i.zero?

          "internal_action_usage" unless external_action_usage?(message)
        end

        # External action usage is defined as any use of an action outside
        # of the organization that created the action.
        def external_action_usage?(message)
          return true if message.value.dig(:connect_request)

          message.value.dig(:resolved_repository, :owner_id, :value) != message.value.dig(:user, :id)
        end

        def increment_repository_usage(repository_id)
          @usage_counts[repository_id] += 1
        end

        def emit_tenant_context_metrics
          return unless GitHub.multi_tenant_enterprise?

          processor_tags = [
            "processor:#{self.class.name&.underscore}",
            "service:#{logical_service}",
          ]
          tags = GitHub::CurrentTenant.metrics_tags + processor_tags
          GitHub.dogstats.increment("tenant_context.hydro_processors", tags: tags)
        end
      end
    end
  end
end
