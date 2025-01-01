# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class CompromisedCredsProcessor < SingleMessageProcessor
      default_to_write_connection!

      STATS_KEY = "compromised_creds_events.messages.processed"
      DEFAULT_GROUP_ID = "compromised_creds_processor"
      DEFAULT_SUBSCRIBE_TO =
        if GitHub.multi_tenant_enterprise?
          /authnd\.credential\.v0\.CompromisedCreds\.Event\Z/
        elsif GitHub.enterprise?
          /authnd\.credential\.enterprise\.v0\.CompromisedCreds\.Event\Z/
        else
          /authnd\.credential\.#{Rails.env}\.v0\.CompromisedCreds\.Event\Z/
        end

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

      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      end

      def process_message(message)
        if GitHub::CompromisedCredentials::Config.should_process_compromised_creds?
          # Extract the fields from the CompromisedCredsEvent message
          encrypted_credential_pair = message.value[:encrypted_credential_pair]
          credential_pair_id = message.value[:credential_pair_id]
          partner_id = message.value[:partner_id]
          breach_id = message.value[:breach_id]
          request_id = message.value[:request_id]
          encryption_key_version = message.value[:encryption_key_version]
          encryption_key = message.value[:encryption_key]
          received_at_utc = message.value[:received_at_utc]

          GitHub.logger.info(
            "Received compromised credentials event",
            "gh.processor.name": self.class.name,
            "gh.credential_pair_id": credential_pair_id,
            "gh.partner_id": partner_id,
            "gh.breach_id": breach_id,
            "gh.request_id": request_id,
            "gh.encryption_key_version": encryption_key_version
          )

          # Skip if we don't have the required encrypted credential pair
          if encrypted_credential_pair.blank?
            GitHub.logger.warn(
              "Skipping compromised credentials event - missing encrypted credential pair",
              "gh.processor.name": self.class.name,
              "gh.credential_pair_id": credential_pair_id,
              "gh.partner_id": partner_id,
              "gh.request_id": request_id
            )
            stats.increment(STATS_KEY, tags: ["partner_id:#{partner_id}", "status:missing_credentials"])
            return message.skip("missing_encrypted_credential_pair")
          end

          stats.increment(STATS_KEY, tags: ["partner_id:#{partner_id}", "status:success"])

          begin
            # Queue the processing job to handle decryption and credential checking
            GitHub::CompromisedCredentials::CompromisedCredsProcessorJob.perform_later(
              encrypted_credential_pair: encrypted_credential_pair,
              credential_pair_id: credential_pair_id,
              partner_id: partner_id,
              breach_id: breach_id,
              encryption_key_version: encryption_key_version,
              request_id: request_id,
              encryption_key: encryption_key
            )

            GitHub.logger.info(
              "Queued compromised credential for processing",
              "gh.processor.name": self.class.name,
              "gh.credential_pair_id": credential_pair_id,
              "gh.partner_id": partner_id
            )

          rescue StandardError => e # rubocop:todo Lint/GenericRescue
            GitHub.logger.error(
              "Failed to queue compromised credential for processing",
              "gh.processor.name": self.class.name,
              "gh.credential_pair_id": credential_pair_id,
              "gh.partner_id": partner_id,
              "gh.error": e.message
            )

            Failbot.report!(e, {
              credential_pair_id: credential_pair_id,
              partner_id: partner_id,
              breach_id: breach_id
            })

            # Re-raise to ensure message is not marked as processed
            raise
          end
        else
          GitHub.logger.info(
            "Skipping compromised credentials event - feature flag disabled",
            "gh.processor.name": self.class.name
          )
          stats.increment(STATS_KEY, tags: ["status:feature_disabled"])
          message.skip("feature_flag_disabled")
        end
      end
    end
  end
end
