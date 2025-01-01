# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class ProgrammaticAccessProcessor < BaseProcessor
      default_to_write_connection!

      STATS_KEY = "programmatic_access_events.messages.processed"
      MAIL_NOTIFICATION_TTL = 1.day
      DEFAULT_GROUP_ID = "programmatic_access_processor"
      DEFAULT_SUBSCRIBE_TO =
        if GitHub.multi_tenant_enterprise?
          /authnd\.credential\.v0\.ProgrammaticAccess\.Event\Z/
        elsif GitHub.enterprise?
          /authnd\.credential\.enterprise\.v0\.ProgrammaticAccess\.Event\Z/
        else
          /authnd\.credential\.#{Rails.env}\.v0\.ProgrammaticAccess\.Event\Z/
        end

      EVENT_TYPES_TO_NOTIFY_OWNER = {
        EXPIRATION_WARNING: :expiration_warning,
        EXPIRED: :expired,
      }

      EVENT_TYPES_TO_INSTRUMENT = {
        EXPIRED: :expired,
        REVOKED: :revoked,
      }

      CATALOG_SERVICES_TO_INSTRUMENT = [
        "github/secret_scanning",
        "authnd-notifier",
        "credentialRevocationAPI"
      ]

      PUBLIC_FACING_REVOKE_EXPLANATIONS = {
        "credentialRevocationAPI" => "An anonymous third party disclosed this credential to GitHub via the credential revocation API",
        "github/secret_scanning" => "The credential was found on GitHub and was revoked by Secret Scanning",
        "default" => "Credential was revoked by GitHub"
      }

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

      resolve_tenant_context do |message|
        tenant_id = message.value[:tenant_id]
        begin
          business = Business.find_by(id: tenant_id)
          next business
        rescue ActiveRecord::RecordNotFound
          GitHub.logger.error(
            "Failed to resolve tenant context.",
            "gh.processor.name": self.class.name,
            "code.function": __method__,
            "gh.business.id": tenant_id,
            "gh.processor.resolve_tenant.failure_reason": "Business not found.",
          )
          raise
        end
      end

      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      end

      def process_message(message)
        event_type, access_id, reason, catalog_service = message.value.values_at(:event_type, :access_id, :event_reason, :catalog_service)

        access = ProgrammaticAccess.find_or_nil(access_id)
        return message.skip("access_not_found") unless access

        if notification_event_type = EVENT_TYPES_TO_NOTIFY_OWNER[event_type]
          notified = access.notify_owner(about: notification_event_type, details: reason)
        end

        should_instrument_event_type = EVENT_TYPES_TO_INSTRUMENT.has_key?(event_type)
        if instrumented = should_instrument_event_type && CATALOG_SERVICES_TO_INSTRUMENT.include?(catalog_service)
          case event_type
          when :REVOKED
            public_facing_explanation = PUBLIC_FACING_REVOKE_EXPLANATIONS[catalog_service] || PUBLIC_FACING_REVOKE_EXPLANATIONS["default"]
            payload = { explanation: public_facing_explanation, reason: }
            access.instrument_credential_revoke(payload)
          when :EXPIRED
            expired_at = Time.at(message.value.values_at(:credential_expires_at_utc).first[:seconds])
            access.instrument_credential_expire({ user_programmatic_access_expired_at: expired_at })
          end
        end

        if instrumented || notified
          stats.increment(STATS_KEY, tags: ["event_type:#{event_type.to_s.downcase}", "notified:#{!!notified}", "instrumented:#{!!instrumented}"])
        end

        message.skip("not_mailer_event") unless notification_event_type
      end
    end
  end
end
