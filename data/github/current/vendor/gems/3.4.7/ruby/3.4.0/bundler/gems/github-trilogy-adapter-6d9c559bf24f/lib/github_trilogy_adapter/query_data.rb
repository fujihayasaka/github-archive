# frozen_string_literal: true

module GitHubTrilogyAdapter
  module QueryData
    extend ActiveSupport::Concern

    prepended do
      attr_reader :last_insert_id, :last_gtid
      private attr_writer :last_insert_id, :last_gtid
    end

    # github/github-kv is currently calling this method passing `nil` instead of
    # a result. If we fix that code we should be able to remove this patch.
    def last_inserted_id(result)
      last_insert_id
    end

    def connection_url
      @connection_url ||= "#{@config[:username] || "root"}@#{@config[:host] || "localhost"}/#{@config[:database]}#{@config[:socket] ? "?socket=#{@config[:socket]}" : "" }"
    end

    private
      def configure_connection
        # Set the query flag to convert all decimals to big decimals.
        # The default behavior changed in https://github.com/trilogy-libraries/trilogy/pull/37
        # but switching over to the new behavior could cause some subtle changes
        # in behavior (e.g. integer vs. float division) so we set this flag to
        # preserve the original behavior.
        @raw_connection.query_flags |= ::Trilogy::QUERY_FLAGS_CAST_ALL_DECIMALS_TO_BIGDECIMALS

        # Populate the connected host so it's available for otel
        # https://github.com/open-telemetry/opentelemetry-ruby-contrib/blob/efaa4040b6e84989efd241d0f988276c83c7a762/instrumentation/trilogy/lib/opentelemetry/instrumentation/trilogy/patches/client.rb#L76
        @raw_connection.connected_host

        super

        if self.class.type_cast_config_to_boolean(@config[:track_gtid])
          internal_execute("SET SESSION session_track_gtids = OWN_GTID")
        end
      end

      def perform_query(...)
        super.tap do |result|
          self.last_insert_id = result.last_insert_id
          self.last_gtid = @raw_connection.last_gtid if @raw_connection.last_gtid
        end
      end
  end
end
