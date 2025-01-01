# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class CheckSuiteStatusChangeProcessor < BaseProcessor
      default_to_write_connection!

      DEFAULT_GROUP_ID = "check_suite_status_change_processor"
      DEFAULT_SUBSCRIBE_TO = /github\.v1\.CheckSuiteStatusChange\Z/

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

      resolve_tenant_context do |message|
        Repositories::Public.resolve_tenant(id: message.value[:repository_id])
      end

      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      end

      def batching?
        false
      end

      # Public: Process a single Hydro message
      #
      # message - The Hydro message to process
      #
      # Returns nothing
      def process_message(message)
        # Pick some check suite info from the message payload to avoid
        # replication lag issues with the `find_by` queries.
        conclusion = message.value[:conclusion]
        status = message.value[:current_status]
        head_sha = message.value[:head_sha]

        # We're only interested in changes where the check suite is complete and it either failed or requires action.
        return message.skip("invalid_check_suite_status") unless status == :COMPLETED && (conclusion == "failure" || conclusion == "action_required")

        ActiveRecord::Base.connected_to(role: :reading) do
          check_suite = CheckSuite.find_by(id: message.value[:check_suite_id])

          return message.skip("invalid_check_suite") if check_suite.nil?
          check_suite_repository = T.must(check_suite.repository)
          matching_pull_requests = check_suite_repository.pull_requests.open_pulls
            .where(head_ref: Git::Ref.safe_ref_name(ref_names: check_suite.head_branch),
                   head_sha: head_sha,
                   head_repository_id: check_suite.head_repository_id || check_suite.repository_id)
            .order(id: :desc)
            .limit(10)

          return message.skip("no_matching_prs") if matching_pull_requests.empty?

          matching_pull_requests.each do |pull_request|
            data = {
              timestamp: check_suite.updated_at,
              type: "pr-checks-failed",
              owner: T.must(check_suite_repository.owner).login,
              repo: check_suite_repository.name,
              pull_request_number: pull_request.number,
              check_suite_id: check_suite.id,
              commit_sha: head_sha,
            }

            next if pull_request.user.nil?

            channel_name = GitHub::WebSocket::Channels.desktop_user(pull_request.user)
            GitHub::WebSocket.notify_pull_request_channel(pull_request, channel_name, data)
          end
        end
      end
    end
  end
end
