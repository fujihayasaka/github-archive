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

      # Twirp client for elm-exporter's MigrationManagerAPI.
      # GHES-only substrate for the customer-facing ELM API. Like #mvnd_client but:
      # reads ELM_EXPORTER_HMAC_KEYS, signs via the gem's HMACMiddleware, and the base
      # URL has NO "/twirp" segment (see #elm_exporter_base_url).
      # Callers MUST gate on #elm_exporter_enabled? — ELM_EXPORTER_HOST is not yet wired
      # into the monolith env, so without it this can't reach a server.
      def elm_exporter_client
        @elm_exporter_client ||= begin
          connection = GitHub::FaradayClient.internal("elm_exporter", elm_exporter_base_url) do |conn|
            conn.use Mvnd::ElmExporter::HMACMiddleware, elm_exporter_hmac_key

            conn.options[:open_timeout] = 1
            conn.options[:timeout] = 5
          end
          Mvnd::ElmExporter::Client.new(connection)
        end
      end

      def elm_exporter_host
        GitHub.environment.fetch("ELM_EXPORTER_HOST", @elm_exporter_host)
      end
      attr_writer :elm_exporter_host

      # ELM_EXPORTER_HMAC_KEYS may hold a comma-separated list during key rotation; the
      # elm-exporter server (hmac.Validator) accepts any key in the list, and all ELM
      # daemons sign with the FIRST (primary) key — see eventlistener/command.go, which
      # does cmdutil.ParseHMACKeys(...)[0]. That parser splits on ",", trims whitespace,
      # and drops empties. The gem's HMACMiddleware signs verbatim and does not split,
      # so we mirror ParseHMACKeys here and select the first key.
      def elm_exporter_hmac_key
        GitHub.environment["ELM_EXPORTER_HMAC_KEYS"].to_s.split(",").map(&:strip).reject(&:empty?).first
      end

      # No "/twirp" suffix — unlike #mvnd_base_url. The generated elm_exporter client
      # posts to the bare "<package>.<Service>/<Rpc>" path.
      def elm_exporter_base_url
        elm_exporter_host
      end

      # Whether the customer-facing ELM API can serve traffic here: GHES single-tenant
      # only, and only once ELM_EXPORTER_HOST is wired in.
      def elm_exporter_enabled?
        return @elm_exporter_enabled if defined?(@elm_exporter_enabled)

        GitHub.single_tenant_enterprise? &&
          (Rails.env.development? || elm_exporter_host.present?)
      end
      attr_writer :elm_exporter_enabled

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
