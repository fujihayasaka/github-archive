# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class StatelessTokenExpirationExtensionProcessor < SingleMessageProcessor
      default_to_write_connection!

      STATS_KEY = "stateless_token_expiration_extension.messages.processed"
      DEFAULT_GROUP_ID = "stateless_token_expiration_extension_processor"
      DEFAULT_SUBSCRIBE_TO =
        if GitHub.multi_tenant_enterprise?
          /authnd\.credential\.v0\.StatelessTokenExpirationExtension\.Event\Z/
        elsif GitHub.enterprise?
          /authnd\.credential\.enterprise\.v0\.StatelessTokenExpirationExtension\.Event\Z/
        else
          /authnd\.credential\.#{Rails.env}\.v0\.StatelessTokenExpirationExtension\.Event\Z/
        end

      VALID_AUTHENTICATABLE_TYPES = %w[
        IntegrationInstallation
        ScopedIntegrationInstallation
        SiteScopedIntegrationInstallation
      ].freeze

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
        unless FeatureFlag.vexi.enabled?(:consume_stateless_token_expiration_extension_events, default: false)
          return message.skip("feature_flag_disabled")
        end

        authenticatable_id, authenticatable_type, extended_expires_at_utc, token_last_eight =
          message.value.values_at(:authenticatable_id, :authenticatable_type, :extended_expires_at_utc, :token_last_eight)

        unless VALID_AUTHENTICATABLE_TYPES.include?(authenticatable_type)
          return message.skip("invalid_authenticatable_type")
        end

        unless extended_expires_at_utc.present?
          return message.skip("missing_extended_expires_at")
        end

        authenticatable = authenticatable_type.constantize.find_by(id: authenticatable_id)
        unless authenticatable
          return message.skip("authenticatable_not_found")
        end

        unless authenticatable.respond_to?(:extend_expires_at) && authenticatable.expires_at.present?
          return message.skip("authenticatable_not_extendable")
        end

        extended_expires_at = Time.zone.at(extended_expires_at_utc[:seconds], extended_expires_at_utc[:nanos], :nsec)

        # Ensure the authenticatable does not expire before the token expires
        new_expires_at = [extended_expires_at, authenticatable.expires_at].max

        authenticatable.extend_expires_at(new_expires_at, entry_point: :stateless_token_expiration_extension, token_last_eight: token_last_eight)

        stats.increment(STATS_KEY, tags: ["authenticatable_type:#{authenticatable_type}"])
      end
    end
  end
end
