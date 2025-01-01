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
        return nil unless schema&.has_visible_fields?
        @object.async_repository_ruleset.then do |ruleset|
          # Once the `rulesets_fix_api_rule_visibility` FF is removed we can remove the source async calls
          ruleset.async_source.then do |source|
            # Owner is called later
            source.async_owner.then do
              # The feature may be enabled, but it may be in beta and we haven't published it to the API
              # This prevents returning data that is not ready for public consumption
              next nil if source.only_show_published_rules? && !impl&.publish_api
              Platform::Models::RepositoryRuleParameters.new(ruleset, @object.parameters, rule_type: @object.rule_type)
            end
          end
        end
      end
    end
  end
end
