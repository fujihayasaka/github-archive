# typed: true
# frozen_string_literal: true

module HierarchyProcessors
  class SubIssueListRecalculationProcessor < GitHub::StreamProcessors::BaseProcessor
    default_to_write_connection!

    DEFAULT_GROUP_ID = "github-#{Rails.env}-sub_issue_list_recalculation_processor"
    DEFAULT_SUBSCRIBE_TO = [
        /github\.v1\.IssueClose\Z/,
        /github\.v1\.IssueReopen\Z/,
        /github\.v1\.SubIssueAdd\Z/,
        /github\.v1\.SubIssueRemove\Z/,
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
      parent_id = case message.schema
      when /hydro.schemas.github.v1.(IssueClose|IssueReopen)/
        issue = with_read { Issue.includes(:parent_issue_relation).find_by(id: message.value.dig(:issue, :id)) }
        return message.skip("missing_closed_issue") unless issue
        issue.parent_issue_relation&.source_issue_id
      when /hydro.schemas.github.v1.(SubIssueAdd|SubIssueRemove)/
        source_issue_id = message.value.dig(:source_issue, :id)
        return message.skip("missing_source_issue") unless source_issue_id
        source_issue_id
      else
        return message.skip("unknown_schema")
      end

      return message.skip("no_parent_to_update") unless parent_id

      # we include sub_issues and sub_issue_list as part of this query so the recalculation below doesn't need to
      # perform additional reads against the primary
      parent_issue = with_read { Issue.includes(:sub_issues, :sub_issue_list).find_by(id: parent_id) }

      return message.skip("no_parent_to_update") unless parent_issue

      with_write { parent_issue.recalculate_sub_issue_list! }
    end
  end
end
