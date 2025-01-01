# frozen_string_literal: true

module AdvisoryDB
  module Config
    module HydroConfig
      # define the hydro topics to subscribe to
      # this should be the suffix only, no "cp1-iad.ingest" prefix
      # NOTE: one can see all the topics in production here: https://tributary.githubapp.com/
      HYDRO_TOPIC_SUFFIXES = %w[
        advisory_db.v0.AdvisoryPrediction
        advisory_db.v0.AdvisoryAlertingEvent
        advisory_db.v0.CVERequest
        advisory_db.v0.RepositoryAdvisoryCurationRequest
        advisory_db.v0.MalwareAdvisories
      ].freeze
      # define a regex that will match all topics
      # this is the regex the primary hydro processor will use to find the topics to subscribe to
      PRIMARY_HYDRO_TOPICS = /#{Regexp.union(HYDRO_TOPIC_SUFFIXES)}\z/
      # in production, the topics simply exist
      # however, in development environment, the kafka instance is clean
      # in order for the primary hydro processor to have topics to subscribe to, they must be first made
      # The logic is handled by #create_kafka_topics_for_dev below
      HYDRO_SITE_PREFIX = ""
      DEV_TOPICS = HYDRO_TOPIC_SUFFIXES.map { |topic| HYDRO_SITE_PREFIX + topic }

      # This is the hydro executor that handles all incoming hydro events, regardless of topic
      # NOTE: The reason there is only one executor, rather than one executor per topic, is because
      # it requires a full rails environment to run the processor, and in a local
      # development environment, that can overuse memory and make the system not work very well.
      # To keep resource consumption reasonable in development environment, there is only a single executor/listener
      # This might have to change if we want to subscribe to a topic that will have much higher load than our current topics
      def primary_hydro_executor
        ::GitHub::Telemetry::Logs.logger.info(
          "Subscribing to matching hydro topics",
          "gh.advisory_inbox.hydro.primary_topics": PRIMARY_HYDRO_TOPICS,
        )
        Hydro::Executor.new(
          processor: ::PrimaryHydroProcessor.new,
          consumer: AdvisoryDB.hydro_consumer(
            subscribe_to: PRIMARY_HYDRO_TOPICS,
          ),
        )
      end

      def hydro_client
        return @hydro_client if defined?(@hydro_client)

        @hydro_client = Hydro::Client.new(environment: Rails.env)
      end

      def hydro_publisher
        return @hydro_publisher if defined?(@hydro_publisher)

        @hydro_publisher = hydro_client.publisher(**hydro_publisher_options)
      end

      def hydro_consumer(subscribe_to:)
        hydro_client.consumer(**hydro_consumer_options(subscribe_to: subscribe_to))
      end

      def send_hydro_publish_error_stat(origin)
        AdvisoryDB.stats.increment("hydro.publish_error", tags: AdvisoryDB.dogtags(class: origin))
      end

      def kafka_client_id
        ENV.fetch("KAFKA_CLIENT_ID", nil)
      end

      private

      KAFKA_GROUP_ID = "advisory_db"

      def hydro_publisher_options
        {
          client_id: kafka_client_id,
          seed_brokers: hydro_kafka_brokers,
          async: false,
          logger: Logger.new("log/hydro.log"),
          client_options: ssl_options,
        }
      end

      def hydro_consumer_options(subscribe_to:)
        {
          subscribe_to: subscribe_to,
          group_id: KAFKA_GROUP_ID,
          seed_brokers: hydro_kafka_brokers,
          # once we get a message, we mark it processed only after we successfully actually process it
          # this way we won't lose a message if there is a bug in our processing of it
          # note the call to mark_message_as_processed in the processor
          automatically_mark_as_processed: false,
          # start_from_beginning applies only to first connection for a consumer group
          # on that first connection, process all messages in the queue,
          # or process only new messages as they arrive
          start_from_beginning: true,
          # Possible Options, we'll use defaults for now
          # min_bytes: 1,
          # max_wait_time: 1.seconds,
          # max_bytes_per_partition: 10.megabytes,
        }.merge(ssl_options)
      end

      # for development, use the HYDRO_KAFKA_BROKERS defined in docker-compose.yaml
      # otherwise, we generally should be using the defaults in hydro-client gem
      # Still we can define this value for production in vault if we need to
      def hydro_kafka_brokers
        ENV.fetch("HYDRO_KAFKA_BROKERS", nil)&.split
      end

      def ssl_options
        if Rails.env.production?
          {
            ssl_ca_cert_file_path: ENV.fetch("SSL_CA_CERT_FILE_PATH"),
          }
        else
          {}
        end
      end

      # in a fresh dev environment the topic will not exist
      # the result is failure to create a consumer until a message is published
      # This makes sure a topic exists in a dev environment
      def create_topic_if_not_exist_dev_only(topic)
        return unless Rails.env.development?

        kafka_client = AdvisoryDB.hydro_publisher.sink.instance_eval { client }
        kafka_client.create_topic(topic)
        ::GitHub::Telemetry::Logs.logger.info(
          "Kafka topic created",
          "gh.advisory_inbox.hydro.dev_topic": topic,
        )
      rescue Kafka::TopicAlreadyExists
        ::GitHub::Telemetry::Logs.logger.info(
          "Kafka topic already existed",
          "gh.advisory_inbox.hydro.dev_topic": topic,
        )
      end
    end

    def create_kafka_topics_for_dev
      DEV_TOPICS.each { |topic| create_topic_if_not_exist_dev_only(topic) }
    end

    include HydroConfig
  end
end
