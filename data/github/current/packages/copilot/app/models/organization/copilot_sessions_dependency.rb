# typed: strict
# frozen_string_literal: true

module Organization::CopilotSessionsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Organization }

  included do
    T.bind(self, T.class_of(Organization))

    has_many :copilot_agent_sessions, class_name: "Copilot::AgentSession", inverse_of: :organization
  end
end
