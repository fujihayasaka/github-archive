# typed: strict
# frozen_string_literal: true

# Publishes MCP server events to Hydro via GlobalInstrumenter.
# Callers pass action + server
module Hydro
  class McpServerEventsPublisher
    ACTIONS = T.let({ install: "INSTALL", authorize: "AUTHORIZE", uninstall: "UNINSTALL" }.freeze, T::Hash[Symbol, String])
    STATUSES = T.let({ success: "SUCCESS", error: "ERROR" }.freeze, T::Hash[Symbol, String])
    TRANSPORTS = T.let({ legacy_sse: "LEGACY_SSE", streamable_http: "STREAMABLE_HTTP" }.freeze, T::Hash[Symbol, String])

    sig { params(action: Symbol, server: McpServer, user: T.nilable(User), context: T.nilable(String)).returns(T::Hash[T.untyped, T.untyped]) }
    def self.publish_success(action:, server:, user:, context:)
      payload = build_event_payload(action, :success, server, user, context)
      publish(payload)
    end

    sig { params(action: Symbol, server: McpServer, user: T.nilable(User), context: T.nilable(String), error: StandardError).returns(T::Hash[T.untyped, T.untyped]) }
    def self.publish_error(action:, server:, user:, context:, error:)
      payload = build_event_payload(action, :error, server, user, context)
      publish(payload)
    end

    class << self
      private

      sig { params(action: Symbol, status: Symbol, server: McpServer, user: T.nilable(User), context: T.nilable(String)).returns(T::Hash[T.untyped, T.untyped]) }
      def build_event_payload(action, status, server, user, context)
        {
          action: ACTIONS.fetch(action),
          user_analytics_tracking_id: user&.analytics_tracking_id,
          mcp_server: {
            database_id: server.id,
            url: server.url,
            transport: TRANSPORTS.fetch(server.transport, "UNKNOWN"),
          },
          status: STATUSES.fetch(status, "UNKNOWN"),
          context: context
        }
      end

      sig { params(payload: T::Hash[T.untyped, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
      def publish(payload)
        GlobalInstrumenter.instrument("mcp_server_event", payload)
        payload
      end
    end
  end
end
