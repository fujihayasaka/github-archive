# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class PullRequestTimelineCommentCreateProcessor < BaseProcessor
      DEFAULT_GROUP_ID = "github-#{Rails.env}-pull_request_timeline_comment_create_processor"
      DEFAULT_SUBSCRIBE_TO = /github\.v1\.PullRequestTimelineCommentCreate\Z/

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
        comment_id = message.value[:issue_comment][:id]

        ActiveRecord::Base.connected_to(role: :reading) do
          comment = IssueComment.find_by(id: comment_id)
          return message.skip("invalid_comment") if comment.nil?

          comment_issue = comment.issue
          return message.skip("invalid_comment_missing_issue") if comment_issue.nil?

          pull_request = comment_issue.pull_request
          return message.skip("not_pull_request") if pull_request.nil?

          pull_request_author = pull_request.user
          comment_user = comment.user
          comment_repo = comment.repository

          return message.skip("missing_comment_user") if comment_user.nil?
          return message.skip("missing_comment_repo") if comment_repo.nil?

          comment_repo_owner = comment_repo.owner
          return message.skip("missing_comment_repo_owner") if comment_repo_owner.nil?

          return message.skip("invalid_pull_request_author") if pull_request_author.nil?
          return message.skip("reviewer_is_author") if comment_user.id == pull_request_author.id
          return message.skip("flag_disabled") unless GitHub.flipper[:desktop_pr_comment_notifications].enabled?(pull_request_author)

          data = {
            timestamp: comment.created_at,
            type: "pr-comment",
            subtype: "issue-comment",
            owner: comment_repo_owner.login,
            repo: comment_repo.name,
            pull_request_number: pull_request.number,
            comment_id: comment_id,
          }

          channel_name = GitHub::WebSocket::Channels.desktop_user(pull_request_author)
          GitHub::WebSocket.notify_pull_request_channel(pull_request, channel_name, data)
        end
      end
    end
  end
end
