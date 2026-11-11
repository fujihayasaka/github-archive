# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module RepositoryRules
      class StatusCheckResult < Platform::Objects::Base
        description "The result of evaluating a single required status check"
        minimum_accepted_scopes ["public_repo"]

        field :context, String,
          description: "The status check results that were considered when evaluating the rule.",
          null: false,
          resolver_method: :status_context

        def status_context
          @object.context
        end

        field :integration, App,
          description: "The status check results that were considered when evaluating the rule.",
          null: true,
          method: :async_integration

        field :result, Enums::StatusState,
          description: "The result of this check",
          null: false

        class << self
          delegate :async_api_can_access?, to: Platform::Interfaces::RepositoryRuleRollup
          delegate :async_viewer_can_see?, to: Platform::Interfaces::RepositoryRuleRollup
        end
      end
    end
  end
end
