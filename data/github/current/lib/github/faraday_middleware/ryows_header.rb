# typed: true
# frozen_string_literal: true

require "base64"

module GitHub
  module FaradayMiddleware
    # Faraday middleware that inserts RYOW (Read Your Own Writes) headers for propagating
    # database replication state to downstream services.
    # This allows services like authnd to strategically fallback to the primary when it detects replication lag.
    #
    # The header format matches authnd's response header format:
    # base64-encoded JSON map of cluster names to last write information.
    class RYOWsHeader < ::Faraday::Middleware
      RYOWS_HEADER = "X-GitHub-RYOWs".freeze

      def call(env)
        return @app.call(env) unless FeatureFlag.vexi.enabled?(:authnd_propagate_ryows_header, default: false)

        if gtid_state = current_gtid_state
          env.request_headers[RYOWS_HEADER] = serialize_gtid_state(gtid_state)
        end

        @app.call(env)
      end

      private

      # Get the current GTID state from the DatabaseSelector::ReplicationState
      # Returns a hash of cluster_name => { gtid: string, time: integer }
      def current_gtid_state
        replication_state = DatabaseSelector::ReplicationState.current
        return nil unless replication_state

        replication_state.to_hash
      end

      # Serialize the GTID state hash to a base64-encoded JSON string for the header
      # This matches the format used by authnd's SetTwirpResponseHeader
      def serialize_gtid_state(gtid_state)
        return nil if gtid_state.nil? || gtid_state.empty?

        json_string = GitHub::JSON.dump(gtid_state)
        Base64.strict_encode64(json_string)
      end
    end
  end
end
