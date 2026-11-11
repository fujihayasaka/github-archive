# typed: true
# frozen_string_literal: true

# We are purposely not including a totalCount field because the underlying CAPI endpoint does not currently
# support it within its main `agents/sessions/resources` endpoint. Once it does, we can add it here and to the
# underlying connection wrapper.
# rubocop:disable GitHub/EnsureConsistentConnections
module Platform
  module Connections
    class CopilotAgentTask < Connections::Base
      implements Interfaces::Offsettable

      required_capabilities [:copilot_agents]

      def nodes
        object.edge_nodes
      end

      def edges
        object.edges
      end
    end
  end
end
# rubocop:enable GitHub/EnsureConsistentConnections
