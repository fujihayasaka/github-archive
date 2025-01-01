# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class StratocasterTimelineUpdatesProcessor < Hydro::Processor
      include GitHub::ServiceMapping

      DEFAULT_GROUP_ID = "stratocaster_timeline_updates"
      DEFAULT_SUBSCRIBE_TO = /#{Stratocaster::TIMELINE_UPDATE_SCHEMA}\Z/
      REVIEW_LAB_SUBSCRIBE_TO = /#{Stratocaster::REVIEW_LAB_TIMELINE_TOPIC}\Z/
      STATS_NAMESPACE = "stratocaster_timeline_updates_processor"

      options[:min_bytes] = 512.kilobytes
      options[:max_wait_time] = 1.second
      options[:max_bytes_per_partition] = 512.kilobytes
      options[:automatically_mark_as_processed] = false

      # When connecting for the first time, should we consume from the start
      # of the topic or only process new messages as they arrive
      # This only applies on the first ever connection for this consumergroup
      options[:start_from_beginning] = false

      attr_reader :filter
      attr_reader :index

      def batching?
        true
      end

      def initialize(group_id: nil, subscribe_to: nil, filter: nil)
        options[:group_id] = group_id || DEFAULT_GROUP_ID
        options[:subscribe_to] = subscribe_to || DEFAULT_SUBSCRIBE_TO

        @filter = filter
        @index = GitHub.stratocaster.index

        Failbot.push(
          stream_processor: self.class.name&.underscore,
          group_id: options[:group_id],
          subscribe_to: options[:subscribe_to].to_s,
        )
      end

      def process_with_consumer(batch, consumer) # rubocop:todo GitHub/DoNotOverrideProccessWithConsumerMethod
        class_name = self.class.name&.underscore
        GitHub.context.push(remote_call_source_datadog_tags: [
          "source_type:stream_processor",
          "stream_processor:#{class_name}",
          "source:stream_processor-#{class_name}",
        ])

        GitHub::CurrentTenant.unscope do
          reset_updates
          GitHub.dogstats.increment("#{STATS_NAMESPACE}.received_batch")
          emit_tenant_context_metrics

          batch.each do |message|
            next if filter && !filter.call(message)

            latency_ms = (Time.now.to_f - message.timestamp.to_f) * 1_000

            GitHub.dogstats.increment("#{STATS_NAMESPACE}.messages", tags: ["partition:#{message.partition}"])
            GitHub.dogstats.distribution("#{STATS_NAMESPACE}.latency", latency_ms.to_i, tags: ["partition:#{message.partition}"])

            batch_index_update(message.value[:index_key], message.value[:event_id])
          end

          GitHub.dogstats.count("#{STATS_NAMESPACE}.indexes_count", @index_updates.length)
          GitHub.logger.info({
            "gh.stratocaster.processor.indexes.count" => @index_updates.length,
            "gh.stratocaster.processor.received_batch_size" => batch.length,
          })

          begin
            GitHub.dogstats.distribution_time("#{STATS_NAMESPACE}.bulk_insert") do
              @index.bulk_insert(@index_updates)
            end
            consumer.mark_message_as_processed(batch.last)
          rescue => e # rubocop:todo Lint/GenericRescue
            GitHub.dogstats.increment("#{STATS_NAMESPACE}.failed", tags: ["error:#{e.class.name.underscore}"])
            Failbot.report(e)
          end
        end
      ensure
        GitHub.context.pop_key(:remote_call_source_datadog_tags)
      end

      private

      def reset_updates
        @index_updates = {}
      end

      def index_updates(index_key)
        @index_updates[index_key] ||= []
      end

      def batch_index_update(index_key, event_id)
        index_updates(index_key).unshift(event_id)
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
