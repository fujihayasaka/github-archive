# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module CommunityInsights
      class ContributionActivityProcessor < SingleMessageProcessor
        DEFAULT_GROUP_ID = "contribution_activity_processor"
        DEFAULT_SUBSCRIBE_TO = [
          /github\.discussions\.v2\.Discussions\Z/,
          /github\.v1\.PullRequestCreate\Z/,
          /github\.domain_events\.v0\.IssueCreated\Z/
        ]

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
          repository_id = message.value.dig(:repository, :id)
          schema = message.schema

          case schema
          when "hydro.schemas.github.discussions.v2.Discussions"
            action = message.value.dig(:action)
            return message.skip("discussion_action_not_created") unless action == :ACTION_DISCUSSION_CREATED
            created_at_seconds = message.value.dig(:action_timestamp, :seconds)
            return message.skip("missing_discussion_created_at_seconds") unless created_at_seconds
            entry_date = Time.at(created_at_seconds).to_datetime.beginning_of_day

            with_write { CommunityInsightsDailyCount.increment(repository_id, entry_date, :discussions_count) }
          when "hydro.schemas.github.v1.PullRequestCreate"
            created_at_seconds = message.value.dig(:pull_request, :created_at, :seconds)
            return message.skip("missing_pull_request_created_at_seconds") unless created_at_seconds
            entry_date = Time.at(created_at_seconds).to_datetime.beginning_of_day

            pull_request_id = message.value.dig(:pull_request, :id)
            does_pr_exist = with_read { PullRequest.where(id: pull_request_id).exists? }
            return message.skip("pull_request_not_found") unless does_pr_exist

            with_write { CommunityInsightsDailyCount.increment(repository_id, entry_date, :pull_requests_count) }
          when "hydro.schemas.github.domain_events.v0.IssueCreated"
            created_at_seconds = message.value.dig(:issue, :created_at, :seconds)
            return message.skip("missing_issue_created_at_seconds") unless created_at_seconds
            entry_date = Time.at(created_at_seconds).to_datetime.beginning_of_day

            issue_id = message.value.dig(:issue, :id)
            issue = with_read { Issue.find_by(id: issue_id) } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
            return message.skip("issue_not_found") unless issue.present?
            return message.skip("issue_is_pr") if issue.pull_request?

            with_write { CommunityInsightsDailyCount.increment(repository_id, entry_date, :issues_count) }
          else
            message.skip("unknown_schema")
          end
        end
      end
    end
  end
end
