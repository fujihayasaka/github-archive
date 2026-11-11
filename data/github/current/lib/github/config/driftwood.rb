# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module DriftwoodConfig
      DEFAULT_BULK_EXPORT_PAGE_SIZE = 2500

      # Is the driftwood service enabled or not.
      def driftwood_enabled?
        return @driftwood_enabled if defined?(@driftwood_enabled)
        if GitHub.driftwood_host
          @driftwood_enabled = true
        else
          @driftwood_enabled = false
        end
      end
      attr_accessor :driftwood_enabled

      def driftwood_host
        GitHub.environment.fetch("DRIFTWOOD_HOST", @driftwood_host)
      end
      attr_writer :driftwood_host

      def driftwood_client_v1
        @driftwood_client_v1 ||= ::Driftwood::V1::Client.new(
          driftwood_host,
          faraday_options: { timeout: 20 },
          hmac_key: driftwood_hmac_key
        )
      end
      attr_writer :driftwood_client_v1

      def driftwood_client_v1_stafftools
        @driftwood_client_v1_stafftools ||= ::Driftwood::V1::Client.new(
          driftwood_host,
          faraday_options: { timeout: 60 },
          hmac_key: driftwood_hmac_key,
        )
      end
      attr_writer :driftwood_client_v1_stafftools

      # How many entries per page are requested
      def driftwood_bulk_export_page_size
        @driftwood_bulk_export_page_size || DEFAULT_BULK_EXPORT_PAGE_SIZE
      end
      attr_writer :driftwood_bulk_export_page_size

      def driftwood_hmac_key
        GitHub.environment["DRIFTWOOD_HMAC_KEY"]
      end

      # Public key to encrypt audit log stream tokens with
      def driftwood_stream_key
        GitHub.environment.fetch("DRIFTWOOD_STREAM_KEY", @driftwood_stream_key)
      end
      attr_writer :driftwood_stream_key

      # Key ID that identifies driftwood_stream_key
      def driftwood_stream_key_id
        GitHub.environment.fetch("DRIFTWOOD_STREAM_KEY_ID", @driftwood_stream_key_id)
      end
      attr_writer :driftwood_stream_key_id

      # Whether streaming is enabled or not for GHES
      def driftwood_ghes_streaming_enabled?
        GitHub.environment.fetch("DRIFTWOOD_GHES_STREAMING_ENABLED", @driftwood_ghes_streaming_enabled)
      end
      attr_writer :driftwood_ghes_streaming_enabled

      # Whether audit log streaming is enabled: either for dotcom for GHES if it's explicitly enabled.
      def driftwood_streaming_enabled?
        return true unless GitHub.enterprise? # Enabled for dotcom
        driftwood_ghes_streaming_enabled? # Conditionally enabled for GHES
      end

      # Whether audit log streaming admin panel is enabled on stafftools (only for dotcom for now)
      def driftwood_streaming_stafftools_enabled?
        !GitHub.enterprise?
      end

      # Indicates if we should use Driftwood Azure Data Explorer audit log queries.
      def driftwood_ade_queries_enabled?
        return false if GitHub.enterprise?
        GitHub.driftwood_enabled?
      end
    end
  end

  extend Config::DriftwoodConfig
end
