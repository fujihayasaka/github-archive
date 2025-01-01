# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module RepositoryRules
      class PullRequestRuleRollup < Platform::Objects::Base
        description "Rollup state representing multiple runs of the `pull_request` rule"
        minimum_accepted_scopes ["public_repo"]

        implements Interfaces::RepositoryRuleRollup

        field :required_reviewers, Integer,
          description: "The number of required reviewers for this rule.",
          null: false

        def required_reviewers
          @object.metadata.required_reviewers
        end

        field :requires_codeowners, Boolean,
          description: "Whether codeowners reviews are required.",
          null: false

        def requires_codeowners
          @object.metadata.requires_codeowners
        end

        field :failure_reasons, [Enums::PullRequestRuleFailureReason],
          description: "Reason codes describing why the rule failed.",
          null: false

        def failure_reasons
          @object.metadata.failure_reasons
        end

        class << self
          delegate :async_api_can_access?, to: Platform::Interfaces::RepositoryRuleRollup
          delegate :async_viewer_can_see?, to: Platform::Interfaces::RepositoryRuleRollup
        end
      end
    end
  end
end
