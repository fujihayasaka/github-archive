# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module SponsorsActivity
      class SponsorshipPendingChangeProcessor < Hydro::Processor
        DEFAULT_GROUP_ID = "sponsors_activity_pending_change"
        DEFAULT_SUBSCRIBE_TO = /sponsors.v1.SponsorshipPendingChange\Z/
        STATS_NAMESPACE = "sponsors_activity_processor.sponsorship_pending_change"

        ProcessingError = Class.new(StandardError)

        options[:min_bytes] = 1.byte
        options[:max_wait_time] = 1.second
        options[:max_bytes_per_partition] = 1.megabyte

        def batching?
          true
        end

        def initialize(group_id: nil, subscribe_to: nil)
          options[:group_id] = group_id || DEFAULT_GROUP_ID
          options[:subscribe_to] = subscribe_to || DEFAULT_SUBSCRIBE_TO

          Failbot.push(
            stream_processor: self.class.name&.underscore,
            group_id: options[:group_id],
            subscribe_to: options[:subscribe_to].inspect,
          )
        end

        def process_with_consumer(batch, consumer) # rubocop:todo GitHub/DoNotOverrideProccessWithConsumerMethod
          class_name = self.class.name&.underscore
          GitHub.context.push(remote_call_source_datadog_tags: [
            "source_type:stream_processor",
            "stream_processor:#{class_name}",
            "source:stream_processor-#{class_name}",
          ])

          GitHub.dogstats.increment("#{STATS_NAMESPACE}.received_batch")

          batch.each do |message|
            GitHub.dogstats.increment("#{STATS_NAMESPACE}.received_message")

            begin
              ::SponsorsActivity.create!(activity_attrs(message))
              consumer.mark_message_as_processed(message)
            rescue ActiveRecord::RecordInvalid => e
              GitHub.dogstats.increment("#{STATS_NAMESPACE}.invalid_message")
              Failbot.report(e, sponsors_activity: activity_attrs(message))
            rescue Freno::Throttler::Error
              GitHub.dogstats.increment("#{STATS_NAMESPACE}.message_throttled")
              raise
            rescue => e # rubocop:todo Lint/RescueException
              GitHub.dogstats.increment("#{STATS_NAMESPACE}.failed_message")
              error = ProcessingError.new(e.message)
              error.set_backtrace(e.backtrace)
              Failbot.report(error, cause: e, sponsors_activity: activity_attrs(message))
              consumer.mark_message_as_processed(message)
            end
          end
        ensure
          GitHub.context.pop_key(:remote_call_source_datadog_tags)
        end

        def activity_attrs(message)
          data = message.value
          sponsorable_id = data.dig(:sponsorship, :maintainer, :id)
          sponsor_id = data.dig(:sponsorship, :sponsor, :id)
          old_tier_id = data.dig(:old_tier, :id)
          new_tier_id = data.dig(:new_tier, :id)
          repository_id = data.dig(:new_tier, :repository_id)
          old_repository_id = data.dig(:old_tier, :repository_id)

          {
            timestamp: Time.at(message.timestamp),
            sponsorable_id: sponsorable_id,
            sponsor_id: sponsor_id,
            sponsors_tier_id: new_tier_id,
            repository_id: repository_id,
            old_sponsors_tier_id: old_tier_id,
            old_repository_id: old_repository_id,
            action: :pending_change,
          }
        end
      end
    end
  end
end
