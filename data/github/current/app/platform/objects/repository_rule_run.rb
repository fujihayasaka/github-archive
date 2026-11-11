# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryRuleRun < Platform::Objects::Base
      description "The output of evaluating a single rule."
      minimum_accepted_scopes ["public_repo"]
      visibility :internal

      model_name "RuleEngine::RuleRun"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_rule_suite.then do |rule_suite|
          rule_suite.async_repository.then do |repo|
            permission.typed_can_access?("Repository", repo)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_rule_suite.then do |rule_suite|
          rule_suite.async_repository.then do |repo|
            permission.typed_can_see?("Repository", repo)
          end
        end
      end

      field :rule_type, Enums::RepositoryRuleType,
        description: "The type of rule run.",
        null: false

      field :rule_configuration, Objects::RepositoryRule,
        description: "The definition of the rule.",
        method: :rule_config,
        null: true

      field :result, Enums::RepositoryRuleEvaluationResult,
        description: "The result of this rule run.",
        null: false

      def result
        @object.allowed? ? "passed" : "failed"
      end

      field :message, String,
        description: "The message describing this rule run.",
        null: true

      field :bypassable, Boolean,
        description: "Whether this rule run can be bypassed by the original pusher.",
        null: false

      def bypassable
        @object.can_bypass?
      end
    end
  end
end
