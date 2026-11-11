# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module RepositoryRules
      class RequiredStatusChecksRuleRollup < Platform::Objects::Base
        description "Rollup state representing multiple runs of the `required_status_checks` rule"
        minimum_accepted_scopes ["public_repo"]

        implements Interfaces::RepositoryRuleRollup

        field :status_check_results, [StatusCheckResult],
          description: "The status check results that were considered when evaluating the rule.",
          null: false

        def status_check_results
          @object.metadata.status_check_results
        end

        class << self
          delegate :async_api_can_access?, to: Platform::Interfaces::RepositoryRuleRollup
          delegate :async_viewer_can_see?, to: Platform::Interfaces::RepositoryRuleRollup
        end
      end
    end
  end
end
