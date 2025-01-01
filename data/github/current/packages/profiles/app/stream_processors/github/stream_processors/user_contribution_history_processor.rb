# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class UserContributionHistoryProcessor < BaseProcessor
      DEFAULT_GROUP_ID = "github-#{Rails.env}-user_contribution_history_processor"
      DEFAULT_SUBSCRIBE_TO = /github\.users\.v1\.ContributionHistoryModified\Z/

      BATCH_SIZE = 1

      options[:session_timeout] = 60.seconds
      options[:socket_timeout] = 65.seconds

      options[:start_from_beginning] = false

      # Wait up to 5 seconds for at least 1 message to be available
      options[:min_bytes] = 5.kilobytes
      options[:max_wait_time] = 5.seconds
      options[:max_bytes_per_partition] = 1.megabytes

      # Public: Configure the Hydro processor
      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      end

      def batching?
        true
      end

      # Public: Process a batch of Hydro messages
      #
      # batch - The batch of Hydro messages to process
      #
      # Returns nothing
      def process_batch(batch)
        all_user_ids = batch.filter_map { |message| message.value.dig(:user, :id) }.sort
        uniq_user_ids = all_user_ids.uniq

        GitHub.dogstats.distribution("user_contribution_history_processor.batch_size", all_user_ids.size)
        GitHub.dogstats.distribution("user_contribution_history_processor.duplicate_count", all_user_ids.size - uniq_user_ids.size)

        uniq_user_ids.each_slice(BATCH_SIZE) do |user_id_batch|
          safe_trigger_heartbeat
          Contribution::Accessor::Cache.bulk_reset_user_namespace(user_id_batch, expires: 2.days.from_now)
        end

        batch.each do |message|
          now = Time.now.to_f
          if message.timestamp.present?
            latency_ms = (now - message.timestamp.to_f) * 1_000
            instrument_message_received(latency_ms)
          end
        end

        consumer.mark_message_as_processed(batch.last)
      end
    end
  end
end
