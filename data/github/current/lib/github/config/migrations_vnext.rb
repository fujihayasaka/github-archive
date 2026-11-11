# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module MigrationsVnextConfig
      def mvnd_client
        @mvnd_client ||= begin
          connection = GitHub::FaradayClient.internal("mvnd", mvnd_base_url) do |conn|
            conn.use Mvnd::Client::HMACMiddleware, mvnd_hmac_key

            conn.options[:open_timeout] = 1
            conn.options[:timeout] = 5
            conn.options[:params_encoder] = Faraday::FlatParamsEncoder
          end
          Mvnd::Client.new(connection)
        end
      end

      def mvnd_host
        GitHub.environment.fetch("MVND_HOST", @mvnd_host)
      end

      def mvnd_hmac_key
        GitHub.environment["MVND_HMAC_KEY"]
      end

      def mvnd_base_url
        [mvnd_host, "twirp"].join("/")
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
