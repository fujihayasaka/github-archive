# typed: strict
# frozen_string_literal: true

module ContextRegion
  class AgentFinderCrumb < Crumb
    sig { override.returns(String) }
    def label
      "Agent Finder"
    end

    sig { override.returns(T.nilable(Symbol)) }
    def path_name
      :agent_finder_path
    end
  end
end
