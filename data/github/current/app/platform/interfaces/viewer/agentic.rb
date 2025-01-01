# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Viewer
      module Agentic
        include Interfaces::Base

        description "Copilot Agentic fields in context of the current viewer."

        required_capabilities [:copilot_agents]

        field :viewer_copilot_agent_creates_channel,
          String, "Channel value for subscribing to live updates for session creations.",
          null: true

        def viewer_copilot_agent_creates_channel
          return unless is_viewer

          GitHub::WebSocket::Channels.signed_copilot_agent_session_create(@object)
        end

        field :viewer_copilot_agent_updates_channel,
          String, "Channel value for subscribing to live updates for session updates.",
          null: true

        def viewer_copilot_agent_updates_channel
          return unless is_viewer

          GitHub::WebSocket::Channels.signed_copilot_agent_session_update(@object)
        end

        field :viewer_copilot_agent_log_updates_channel,
          String, "Channel value for subscribing to live updates for session log updates.",
          null: true

        def viewer_copilot_agent_log_updates_channel
          return unless is_viewer

          GitHub::WebSocket::Channels.signed_copilot_agent_session_log_update(@object)
        end

        field :viewer_copilot_agent_sessions,
          Connections.define(Objects::CopilotAgentSession),
          null: false,
          description: "Lists all Copilot Agents Sessions for the viewer",
          connection: true do
            argument :order_by,
              Inputs::CopilotAgentSessionOrder,
              "How to order the returned sessions.",
              required: false,
              default_value: { field: "created_at", direction: "DESC" }
          end

        def viewer_copilot_agent_sessions(order_by: nil)
          # Ensure we limit the results to only the current viewer's sessions. If the viewer is not the
          # user we are looking to resolve then return no results.
          return ArrayWrapper.new([]) unless is_viewer

          # Gate this for internal testing (for now) while we gather benchmarks and further refine
          # the object modeling, CAPI calls, and performance tuning.
          # For example: this should _not_ be used in production outside of internal testing until we ensure
          # we have properly minimized all underlying network calls to the Copilot API.
          return ArrayWrapper.new([]) unless @context[:viewer].feature_flag_enabled?(:graphql_copilot_agents, default: false)

          # Leverage the CopilotSweAgent class to fetch the agent sessions for the viewer.
          # Sort this by created_at descending to help stabilize pagination for clients.
          # This should be deferred to CopilotSweAgent (and the Copilot API) in the future.
          token = Copilot::DecryptedToken.from(@context[:request_token].to_s)
          agent_sessions = CopilotSweAgent::AgentSession.for_user(
            user: @context[:viewer],
            entry_point: :agent_session_for_user_via_graphql,
            user_session: @context[:user_session],
            token:
          )

          # Default to sorting by created_at descending but allow for other orderings as allowed.
          agent_sessions =
            if order_by && order_by[:field] == "created_at" && order_by[:direction] == "ASC"
              agent_sessions.sort_by(&:created_at)
            else
              agent_sessions.sort_by(&:created_at).reverse
            end

          ArrayWrapper.new(agent_sessions)
        end

        field :viewer_copilot_agent_session,
          Objects::CopilotAgentSession,
          null: true,
          description: "Fetches a specific Copilot Agent Session for the viewer." do
            argument :session_id,
              String,
              "The Copilot Agent session identifier to fetch.",
              required: true
          end

        def viewer_copilot_agent_session(session_id:)
          return nil unless is_viewer

          # Feature flag gate to keep this in internal testing for now.
          return nil unless @context[:viewer].feature_flag_enabled?(:graphql_copilot_agents, default: false)

          token = Copilot::DecryptedToken.from(@context[:request_token].to_s)
          session = CopilotSweAgent::AgentSession.for_session(
            user: @context[:viewer],
            session_id: session_id,
            entry_point: :agent_session_for_user_via_graphql_single,
            user_session: @context[:user_session],
            token:
          )

          session || raise(Errors::NotFound, "Could not resolve to a Copilot Agent session with the ID of '#{session_id}'.")
        end

        private

        def is_viewer
          @object == @context[:viewer]
        end
      end
    end
  end
end
