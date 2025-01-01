# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class OauthAccessProcessor < BaseProcessor
      default_to_write_connection!

      STATS_KEY = "oauth_access_events.messages.processed"
      DEFAULT_GROUP_ID = "oauth_access_processor"
      DEFAULT_SUBSCRIBE_TO =
        if GitHub.multi_tenant_enterprise?
          /authnd\.credential\.v0\.OauthAccess\.Event\Z/
        elsif GitHub.enterprise?
          /authnd\.credential\.enterprise\.v0\.OauthAccess\.Event\Z/
        else
          /authnd\.credential\.#{Rails.env}\.v0\.OauthAccess\.Event\Z/
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

      resolve_tenant_context do |message|
        tenant_id = message.value[:tenant_id]
        begin
          business = Business.find(tenant_id)
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
        if GitHub.flipper[:write_authnd_oauth_access_events].enabled?
          event_type, access_id, reason, accessed_at_utc = message.value.values_at(:event_type, :access_id, :event_reason, :accessed_at_utc)

          access = OauthAccess.find_by(id: access_id)
          return message.skip("access_not_found") unless access

          stats.increment(STATS_KEY, tags: ["event_type:#{event_type.to_s.downcase}"])
          if event_type == :ACCESSED
            access.bump!(Time.at(accessed_at_utc[:seconds]))
          else
            message.skip("unsupported_event_type")
          end
        end
      end
    end
  end
end
