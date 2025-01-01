# typed: true
# frozen_string_literal: true

require "github_fe_core/client"
require "github_fe_core/experiment_response_hydro_publisher"

module GitHub
  module StreamProcessors
    class GitHubFeCoreForwardingProcessor < BaseProcessor
      DEFAULT_GROUP_ID = "github-#{Rails.env}-github_fe_core_forwarding_processor"
      DEFAULT_SUBSCRIBE_TO = /github\.experiment\.v1\.ExperimentResponse\Z/

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
        return unless GitHub.flipper[:hydro_github_fe_core_forwarding_processor].enabled?

        if message.value.key?(:request_id)
          request_id = message.value.dig(:request_id)
          GitHub.context.push(request_id: request_id)
        end

        method = message.value.dig(:method)
        route = message.value.dig(:route)
        path = message.value.dig(:path)
        query = message.value.dig(:query)
        request_headers = message.value.dig(:request_headers)

        # Do nothing if the path does not match what we expect:
        return unless method == "GET" && route == "/internal/gists/:id"

        response = github_fe_core_client.internal_request(path: path, params: query, headers: request_headers)

        request = {
          method:,
          path:,
          query:,
          request_headers:,
          route:,
          request_id:,
        }

        GitHubFeCore::ExperimentResponseHydroPublisher.publish_github_fe_core(
          route:,
          request:,
          response:,
        )
      end

      private

      sig { returns GitHubFeCore::Client }
      def github_fe_core_client
        @github_fe_core_client ||= GitHubFeCore::Client.new
      end
    end
  end
end
