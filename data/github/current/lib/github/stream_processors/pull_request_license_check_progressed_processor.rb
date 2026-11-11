# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class PullRequestLicenseCheckProgressedProcessor < SingleMessageProcessor
      include TransientErrorResiliency

      DEFAULT_GROUP_ID = "github-#{Rails.env}-pull_request_license_check_progressed_processor"
      DEFAULT_SUBSCRIBE_TO = /github\.dependencygraph\.v1\.PullRequestLicenseCheckProgressed\Z/

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

      resolve_tenant_context do |message|
        repo_id = message.value.dig(:repository_id)
        Repositories::Public.get_active_or_deleted(repo_id)&.owner&.business
      end

      # Public: Configure the Hydro processor
      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      end

      # Processes an individual message from Hydro.
      #
      # This is the main hook that you must implement.
      #
      # For individual message processing (in a subclass of `SingleMessageProcessor`), this method will be called once
      # per consumer invocation. For batch message processing (in a subclass of `BatchedMessageProcessor`), the
      # default implementation of `process_batch` will call this method in a loop, once for each message in the batch
      # to be processed by a single consumer invocation.
      #
      # @param message - An individual GitHub::StreamProcessors::Message, which represents a Hydro event.
      #
      # @returns An arbitrary value that sub-classes may use for internal testing but that is ignored by this base
      #   class and all framework code in production.
      sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
      def process_message(message)
        event = message.value
        head_sha = event[:commit_sha]

        repo = Repositories::Public.get_active_or_deleted(event[:repository_id])

        return message.skip("Repository not found") if repo.nil?

        unless FeatureFlag.vexi.enabled?(:dependency_graph_license_compliance, repo, repo.owner, repo.business, default: false)
          return message.skip("License compliance feature not enabled")
        end

        return message.skip("Missing head_sha") if head_sha.blank?

        check_job_status = Hydro::Schemas::Github::Dependencygraph::V1::Entities::CheckJobStatus.resolve(event[:check_job_status])
        unless check_job_status
          return message.skip("Invalid check job status")
        end

        return message.skip("Missing progressed_at") if event[:progressed_at].nil?
        progressed_at = Google::Protobuf::Timestamp.new(event[:progressed_at]).to_time
        title = event[:title] ? Google::Protobuf::StringValue.new(event[:title]).value : nil

        with_write do
          check_suite, is_new = CheckRun.create_or_update_license_compliance_check_run!(repo: repo, head_sha: head_sha, check_job_status: check_job_status, log_message: event[:log_message], progressed_at: progressed_at, title: title.presence)

          # Only run the skipping queries when we receive an event for a new commit
          if is_new
            head_branch = check_suite.head_branch
            if head_branch.present?
              CheckRun.skip_old_license_compliance_check_runs!(
                repo: repo,
                head_branch: head_branch,
              )
            end
          end
        end
      end
    end
  end
end
