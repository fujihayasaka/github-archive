# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module MigrationsVnextConfig
      def mvnd_client
        @mvnd_client ||= ::Mvnd::Client.new(
          mvnd_host,
          faraday_options: { timeout: 20 },
          hmac_key: mvnd_hmac_key
        )
      end

      def mvnd_host
        GitHub.environment.fetch("MVND_HOST", @mvnd_host)
      end

      def mvnd_hmac_key
        GitHub.environment["MVND_HMAC_KEY"]
      end

      # Determine if ELM internal webhooks are enabled
      # - Disabled for dotcom
      # - Disabled for enterprise by default, except if explicitly enabled via ghe-config apply. Checks for ENTERPRISE_ELM_INTERNAL_WEBHOOKS_ENABLED variable.
      #
      # Returns true if enabled, false otherwise.
      def elm_internal_webhooks_enabled?
        return false unless GitHub.enterprise?
        return @elm_internal_webhooks_enabled if defined?(@elm_internal_webhooks_enabled)
        @elm_internal_webhooks_enabled = false
      end
      attr_writer :elm_internal_webhooks_enabled

      # The port used by the elm-exporter-event-listener service for webhook delivery.
      ELM_WEBHOOKS_ALLOWED_PORT = 9178

      # Public: Returns the port used by the ELM webhooks service.
      #
      # Returns an Integer.
      def elm_webhooks_allowed_port
        ELM_WEBHOOKS_ALLOWED_PORT
      end

      # Determine if ELM webhooks loopback addresses are enabled. The elm-exporter-event-listener service on GHES
      #   uses the http://localhost:9178/api/v1/webhooks endpoint to receive webhook events from GHES to power
      #   the live migrations feature. We need to be able to configure webhooks on a specific port to allow this
      #   functionality to work.
      #
      # - Disabled for dotcom
      # - Disabled for enterprise by default, except if explicitly enabled via ghe-config apply. Checks for ENTERPRISE_ELM_WEBHOOKS_LOOPBACK_ADDRESS_ENABLED variable.
      #
      # Returns true if enabled, false otherwise.
      def elm_webhooks_loopback_address_enabled?
        return false unless GitHub.enterprise?
        return @elm_webhooks_loopback_address_enabled if defined?(@elm_webhooks_loopback_address_enabled)
        @elm_webhooks_loopback_address_enabled = false
      end
      attr_writer :elm_webhooks_loopback_address_enabled

    end
  end

  extend Config::MigrationsVnextConfig
end
