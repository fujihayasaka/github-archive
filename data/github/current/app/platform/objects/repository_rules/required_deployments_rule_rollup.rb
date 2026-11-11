# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module RepositoryRules
      class RequiredDeploymentsRuleRollup < Platform::Objects::Base
        description "Rollup state representing multiple runs of the `required_deployments` rule"
        minimum_accepted_scopes ["public_repo"]

        implements Interfaces::RepositoryRuleRollup

        field :missing_environments, [String],
          description: "The environments that were required to be deployed to, but were not.",
          null: false

        def missing_environments
          @object.metadata.missing_environments
        end

        field :deployed_environments, [String],
          description: "The environments that were required to be deployed to and were.",
          null: false

        def deployed_environments
          @object.metadata.deployed_environments
        end

        class << self
          delegate :async_api_can_access?, to: Platform::Interfaces::RepositoryRuleRollup
          delegate :async_viewer_can_see?, to: Platform::Interfaces::RepositoryRuleRollup
        end
      end
    end
  end
end
