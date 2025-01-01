# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class RefreshTokenProcessor < BaseProcessor
      include TransientErrorResiliency

      DEFAULT_GROUP_ID = "github-#{Rails.env}-refresh_token_processor"
      DEFAULT_SUBSCRIBE_TO = /github\.external_identity\.v0\.RefreshToken\Z/
      REQUIRED_VALUES = %w[external_identity_id refresh_token]

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

      resolve_tenant_context do |message|
        external_identity = ExternalIdentity.find_by(id: message.value[:external_identity_id])
        external_identity&.target
      end

      # Public: Process a single Hydro message
      #
      # message - The Hydro message to process
      #
      # Returns nothing
      def process_message(message)
        GitHub.logger.info(
          "Received message",
          "code.namespace" => self.class.name,
          "code.function" => "process_message",
          "messaging.kafka.message.offset" => message.offset,
          "message.arguments" => message.value,
        )

        external_identity_id = message.value[:external_identity_id]
        refresh_token = message.value[:refresh_token]
        client_ip = message.value[:client_ip]
        cache_value = message.value[:cache_value]

        if missing_required_values?(message)
          GitHub.logger.error("Missing required values",
            {
              "code.namespace" => self.class.name,
              "code.function" => "process_message",
              "gh.external_identities.id" => external_identity_id,
              "gh.external_identities.refresh_token_size" => refresh_token&.bytesize,
              "gh.external_identities.client_ip" => client_ip,
              "gh.external_identities.cache_value" => cache_value,
            }
          )
          return message.skip("missing_required_values")
        end

        external_identity = ExternalIdentity.where(id: external_identity_id)
          .includes(provider: :target).first

        if external_identity.nil?
          GitHub.logger.error("External identity not found",
            {
              "code.namespace" => self.class.name,
              "code.function" => "process_message",
              "gh.external_identities.id" => external_identity_id,
            }
          )
          return message.skip("external_identity_not_found")
        end

        if client_ip && cache_value
          OIDC::CapValidatorCache.write(external_identity.target, external_identity, client_ip, cache_value)
        end

        ActiveRecord::Base.connected_to(role: :writing) do
          external_identity.set_refresh_token(refresh_token)
        end
      end

      private

      def log_error(external_identity, refresh_token, message = "Unable to set refresh token from AAD")
        GitHub.logger.error(message,
          {
            "code.namespace" => self.class.name,
            "code.function" => "process_message",
            "gh.business.name" => external_identity.target.slug,
            "gh.external_identities.oid" => external_identity.external_id,
            "gh.external_identities.id" => external_identity.id,
            "gh.external_identities.refresh_token_size" => refresh_token&.bytesize,
          }
        )
      end

      def missing_required_values?(message)
        REQUIRED_VALUES.any? do |key|
          message.value[key.to_sym].nil? || message.value[key.to_sym] == "" || message.value[key.to_sym] == 0
        end
      end
    end
  end
end
