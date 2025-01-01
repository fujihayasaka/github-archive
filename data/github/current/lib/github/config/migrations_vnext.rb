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

    end
  end

  extend Config::MigrationsVnextConfig
end
