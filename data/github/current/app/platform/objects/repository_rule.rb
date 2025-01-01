# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryRule < Platform::Objects::Base
      description "A repository rule."
      minimum_accepted_scopes ["public_repo"]

      model_name "RepositoryRuleConfiguration"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, rule)
        rule.async_repository_ruleset.then do |ruleset|
          permission.typed_can_access?("RepositoryRuleset", ruleset)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, rule)
        rule.async_repository_ruleset.then do |ruleset|
          permission.typed_can_see?("RepositoryRuleset", ruleset)
        end
      end

      implements_node templates: [[:rru, :ruleset_id, :id]], as: "RRU", ready_date: Platform::Helpers::GlobalId::COHORT_5 do |rule|
        rule.async_repository_ruleset.then do |ruleset|
          { prefix: :rru, ruleset_id: ruleset.id, id: rule.id }
        end
      end

      field :repository_ruleset, RepositoryRuleset,
        description: "The repository ruleset associated with this rule configuration",
        method: :async_repository_ruleset,
        null: true

      field :type, Enums::RepositoryRuleType,
        description: "The type of rule.",
        method: :rule_type,
        null: false

      field :parameters, Unions::RuleParameters,
        description: "The parameters for this rule.",
        null: true

      def parameters
        return nil unless @object.parameters.present?
        impl = RuleEngine::Evaluator.rule_impl_for_rule_type(@object.rule_type)
        schema = impl.try(:parameter_schema)
        # If there are no visible fields then there are no params
        # This also prevents returning data that is not ready for public consumption
        return nil unless schema&.has_visible_fields?

        @object.async_repository_ruleset.then do |ruleset|
          ruleset.async_source.then do |source|
            # include the rule params if
            # 1. The rule is published
            # OR
            # 2. The rule is feature flagged, the feature flag is enabled, and provided in the request headers.
            if impl&.publish_api || (impl&.feature_flag.present? && source&.feature_enabled_for_source?(impl&.feature_flag) && @context[:feature_flags].include?(impl&.feature_flag))
              Platform::Models::RepositoryRuleParameters.new(ruleset, @object.parameters, rule_type: @object.rule_type)
            end
          end
        end
      end
    end
  end
end
