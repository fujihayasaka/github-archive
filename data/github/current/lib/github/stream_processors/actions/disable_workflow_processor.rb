# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Actions
      class DisableWorkflowProcessor < BaseProcessor
        DEFAULT_GROUP_ID = "github-#{Rails.env}-actions_disable_workflow_processor"
        DEFAULT_SUBSCRIBE_TO = /github\.actions\.v0\.WorkflowDisable\Z/

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
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        # Public: Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        def process_message(message)
          GitHub.dogstats.increment("actions_disable_workflow.hydro_message.process")

          repo = repository(message)
          if repo.nil?
            message.skip("repo_not_found")
            return nil
          end

          workflow_file_path = message.value[:workflow_file_path]
          if workflow_file_path.nil? || workflow_file_path.empty?
            message.skip("workflow_file_path_empty")
            return nil
          end

          if !repo.feature_enabled?(:actions_disable_workflow_processor)
            GitHub.logger.info({
              msg: "Skipping workflow disable operation because the feature flag is disabled",
              workflow_file_path: workflow_file_path,
              repository_id: repo.id,
              repository_name: repo.name,
            })
            message.skip("actions_disable_workflow_processor_disabled")
            return nil
          end

          workflow = repo.workflows.find_from_filename(workflow_file_path)
          if workflow.nil?
            message.skip("workflow_not_found")
            return nil
          end

          if workflow.disabled?
            message.skip("workflow_already_disabled")
            return nil
          end

          if !workflow.disableable?
            message.skip("workflow_not_disableable")
            return nil
          end

          GitHub.logger.info({
            msg: "Disabling workflow from actions_disable_workflow_processor",
            workflow_id: workflow.id,
            workflow_file_path: workflow_file_path,
            repository_id: repo.id,
            repository_name: repo.name,
          })

          with_write do
            workflow.disable(User.staff_user)
          end
        end

        def repository(message)
          repo_id = if !message.value[:repository_database_id].zero?
            message.value[:repository_database_id]
          else
            Platform::Helpers::NodeIdentification.from_global_id(message.value[:global_id]).last
          end

          Repositories::Public.find_active(repo_id)
        end
      end
    end
  end
end
