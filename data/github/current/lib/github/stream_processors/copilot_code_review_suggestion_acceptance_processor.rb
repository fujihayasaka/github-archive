# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class CopilotCodeReviewSuggestionAcceptanceProcessor < SingleMessageProcessor
      DEFAULT_GROUP_ID = "github-#{Rails.env}-copilot_code_review_suggestion_acceptance_processor"
      DEFAULT_SUBSCRIBE_TO = [
        /github\.v1\.PullRequestMerge\Z/,
        /github\.v1\.PullRequestClose\Z/
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
        pull_id = message.value[:pull_request][:id]
        return message.skip("missing pull request ID") unless pull_id.present?

        ActiveRecord::Base.connected_to(role: :reading) do
          pull_request = PullRequest.find_by(id: pull_id)
          return message.skip("unable to find pull request") unless pull_request.present?
          return message.skip("must be in copilot_code_review_suggestion_acceptance flag") unless pull_request.repository&.feature_enabled_for_repo_or_owner?(:copilot_code_review_suggestion_acceptance)

          analyzer = PullRequests::Copilot::CodeReview::SuggestionAcceptanceAnalyzer::Analyzer.new(pull_request:)
          analyzer.analyze
        end
      end
    end
  end
end
