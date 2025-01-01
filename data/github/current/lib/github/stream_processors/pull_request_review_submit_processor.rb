# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class PullRequestReviewSubmitProcessor < SingleMessageProcessor
      default_to_write_connection!

      DEFAULT_GROUP_ID = "github-#{Rails.env}-pull_request_review_submit_processor"
      DEFAULT_SUBSCRIBE_TO = /github\.v1\.PullRequestReviewSubmit\Z/
      VALID_REVIEW_STATES = [:CHANGES_REQUESTED, :APPROVED, :COMMENTED].freeze

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
        review_state = message.value[:pull_request_review][:state]
        review_id = message.value[:pull_request_review][:id]

        return message.skip("invalid_review_state") unless VALID_REVIEW_STATES.include?(review_state)

        ActiveRecord::Base.connected_to(role: :reading) do
          review = PullRequestReview.find_by(id: review_id)
          return message.skip("invalid_review") if review.nil?

          pull_request = review.pull_request
          return message.skip("invalid_pull_request") if pull_request.nil?

          pull_request_author = pull_request.user
          return message.skip("invalid_pull_request_author") if pull_request_author.nil?

          review_user = review.user

          return message.skip("reviewer_missing") if review_user.nil?
          return message.skip("reviewer_is_author") if pull_request_author.id == review_user.id

          review_repo = review.repository

          return message.skip("review_repo_missing") if review_repo.nil?

          review_repo_owner = review_repo.owner

          return message.skip("review_repo_missing_owner") if review_repo_owner.nil?

          # If the review is a single comment, we want to notify the author of the PR like it was just a comment and
          # not a review.
          if review_state == :COMMENTED &&
            review.review_comments.length == 1 &&
            review.body.blank?

            data = {
              timestamp: review.submitted_at,
              type: "pr-comment",
              subtype: "review-comment",
              owner: review_repo_owner.login,
              repo: review_repo.name,
              pull_request_number: pull_request.number,
              comment_id: review.review_comments[0].id,
            }
          else
            data = {
              timestamp: review.submitted_at,
              type: "pr-review-submit",
              owner: review_repo_owner.login,
              repo: review_repo.name,
              state: review_state.to_s,
              pull_request_number: pull_request.number,
              review_id: review_id,
              number_of_comments: review.review_comments.length,
            }
          end

          channel_name = GitHub::WebSocket::Channels.desktop_user(pull_request_author)
          GitHub::WebSocket.notify_pull_request_channel(pull_request, channel_name, data)
        end
      end
    end
  end
end
