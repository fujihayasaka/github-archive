# typed: strict
# frozen_string_literal: true

module Copilot
  class AgentSession < ApplicationRecord::Copilot
    include ::Instrumentation::Model
    include Copilot::Helpers
    include ::Repositories::BelongsToRepository

    self.table_name = "copilot_agent_sessions"
    self.strict_loading_by_default = true

    belongs_to :business, class_name: "::Business", inverse_of: :copilot_agent_sessions
    belongs_to :organization, class_name: "::Organization", inverse_of: :copilot_agent_sessions
    belongs_to_repository_via_domain
    belongs_to :user, class_name: "::User"

    belongs_to :agent, polymorphic: true, optional: false
    belongs_to :resource, polymorphic: true
    validates :agent_id, presence: true
    validates :agent_type, presence: true, inclusion: { in: %w(Integration OauthApplication) }
    validates :resource_type, allow_blank: true, inclusion: { in: %w[PullRequest] }
  end
end
