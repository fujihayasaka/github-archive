# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class EnterpriseServerActionsUsageProcessor < BaseProcessor
      default_to_write_connection!

      include TransientErrorResiliency

      DEFAULT_GROUP_ID = "github-#{Rails.env}-enterprise_server_actions_usage_processor"
      DEFAULT_SUBSCRIBE_TO = /github\.actions\.v0\.JobExecution\Z/
      REQUIRED_VALUES = %w[invoking_event_type workflow_repository_id workflow_repository_global_id
        workflow_repository_visibility workflow_build_id job_id job_runtime check_run_id start_time
        end_time runner_type]

      # This is the timeout used for determining if a given Kafka consumer has
      # failed or quit due to e.g. a deploy. Setting it to a lower value is NOT
      # recommended if your Hydro processor interacts with the database, since
      # Freno may wait up to 30 seconds when throttling writes. Processors that
      # do not interact with a database may lower this value to allow faster
      # consumer group rebalancing during deploys and processor failures.
      #
      # See https://kafka.apache.org/documentation/#session.timeout.ms
      options[:session_timeout] = 60.seconds

      # This value must be greater than "session_timeout"
      #
      # See https://github.com/zendesk/ruby-kafka#understanding-timeouts
      options[:socket_timeout] = 65.seconds

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
      def setup(**kwargs)
        GitHub::Logger.warn("EnterpriseServerActionsUsageProcessor should only run in enterprise mode") unless GitHub.enterprise?
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      end

      # Public: Process a single Hydro message
      #
      # message - The Hydro message to process
      #
      # Returns nothing
      def process_message(message)
        return unless GitHub.enterprise?

        if missing_required_values?(message)
          return message.skip("missing_required_values")
        end

        # If negative duration then skip the line item. Could indicate a bug in the job
        return message.skip("zero_duration") unless message.value[:job_execution_billable_ms].positive?

        repo = ActiveRecord::Base.connected_to(role: :reading) { Repository.find_by(id: message.value[:workflow_repository_id]) }
        # Repos are soft-deleted, and hard-deleted after 30 days. Therefore, check both nil and deleted?.
        if repo.nil? || repo.deleted?
          return message.skip("repo_deleted")
        end

        job_execution = {
          event_id: message.id,
          invoking_event_type: message.value[:invoking_event_type],
          workflow_repository_id: message.value[:workflow_repository_id],
          workflow_repository_global_id: message.value[:workflow_repository_global_id],
          workflow_repository_visibility: message.value[:workflow_repository_visibility].to_s,
          workflow_build_id: message.value[:workflow_build_id],
          job_id: message.value[:job_id],
          job_runtime: message.value[:job_runtime].to_s,
          job_runtime_version: message.value[:job_runtime_version],
          job_check_suite_id: message.value[:check_suite_id],
          job_check_run_id: message.value[:check_run_id],
          started_at: Time.at(message.value[:start_time][:seconds]),
          finished_at: Time.at(message.value[:end_time][:seconds]),
          job_execution_billable_ms: message.value[:job_execution_billable_ms],
          runner_properties: message.value[:runner_properties],
          runner_type: message.value[:runner_type].to_s,
          organization_id: repo.organization_id,
        }

        begin
          job_check_run_conclusion = begin
            run = Checks.domain.check_runs.unsafe_for_id(message.value[:check_run_id])
            run[:conclusion] if run
          end
          if !job_check_run_conclusion.nil?
            job_execution[:job_check_run_conclusion] = job_check_run_conclusion.to_s
          end
          rescue ActiveRecord::RecordNotFound, ActiveRecord::SoleRecordExceeded
            nil
        end

        begin
          GhesActionsJobExecution.create!(job_execution)
        rescue ActiveRecord::RecordNotUnique
          message.skip("duplicate")
        end
      end

      def missing_required_values?(message)
        REQUIRED_VALUES.any? do |key|
          message.value[key.to_sym].nil? || message.value[key.to_sym] == "" || message.value[key.to_sym] == 0
        end
      end
    end
  end
end
