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

      # ELM_EXPORTER_HMAC_KEYS may be a comma-separated list during key rotation. The
      # server accepts any key in the list; ELM daemons sign with the FIRST one (see
      # eventlistener/command.go: cmdutil.ParseHMACKeys(...)[0]). The gem's middleware
      # signs verbatim, so we mirror that parsing and pick the first key.
      def elm_exporter_hmac_key
        GitHub.environment["ELM_EXPORTER_HMAC_KEYS"].to_s.split(",").map(&:strip).reject(&:empty?).first
      end

      # The elm-exporter Twirp server mounts at /twirp (standard twitchtv/twirp
      # PathPrefix(); see github/elm-exporter internal/pkg/twirp/server.go). The
      # generated client adds only the "/<package>.<service>/<rpc>" service path, so
      # the base URL MUST include /twirp, exactly like #mvnd_base_url. Do not remove it.
      def elm_exporter_base_url
        [elm_exporter_host, "twirp"].join("/")
      end

      # Whether the customer-facing ELM API can serve traffic here. GHES single-tenant
      # only, and only when elm-exporter is explicitly enabled. We gate on
      # ENTERPRISE_ELM_EXPORTER_ENABLED, NOT host-presence:
      # ELM_EXPORTER_HOST is now always set, but its localhost:1738 listener only exists
      # when enabled. Host is kept as a secondary guard.
      def elm_exporter_enabled?
        return @elm_exporter_enabled if defined?(@elm_exporter_enabled)

        GitHub.single_tenant_enterprise? &&
          (Rails.env.development? ||
            (GitHub.environment["ENTERPRISE_ELM_EXPORTER_ENABLED"] == "true" && elm_exporter_host.present?))
      end
      attr_writer :elm_exporter_enabled

      # Whether ELM internal webhooks are enabled. Disabled for dotcom; disabled for
      # enterprise unless enabled via ghe-config apply (ENTERPRISE_ELM_INTERNAL_WEBHOOKS_ENABLED).
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

      # Whether ELM webhooks loopback addresses are enabled. The event-listener service
      # on GHES receives webhooks at http://localhost:9178/api/v1/webhooks, so this port
      # must be allowed. Disabled for dotcom; disabled for enterprise unless enabled via
      # ghe-config apply (ENTERPRISE_ELM_WEBHOOKS_LOOPBACK_ADDRESS_ENABLED).
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
