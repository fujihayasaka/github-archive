# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryRuleset < Platform::Objects::Base
      description "A repository ruleset."
      minimum_accepted_scopes ["public_repo"]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, ruleset)
        # Use the source node, if set, to determine if the viewer
        # has access to the ruleset via the node (e.g. An inherited ruleset)
        ruleset.async_source_node.then do |source|
          if source.is_a?(::Repository)
            # users with access to a repo can see the rulesets
            permission.typed_can_access?("Repository", source)
          elsif source.is_a?(::Organization)
            permission.access_allowed?(:manage_organization_ref_rules, resource: source, current_repo: nil, current_org: source, allow_integrations: true, allow_user_via_granular_actor: true)
          elsif source.is_a?(::Business)
            permission.access_allowed?(:administer_business, resource: source, repo: nil, organization: nil, allow_integrations: true, allow_user_via_granular_actor: true)
          else
            false
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, ruleset)
        ruleset.async_source_node.then do |source|
          if source.is_a?(::Repository)
            permission.typed_can_see?("Repository", source)
          elsif source.is_a?(::Organization)
            permission.typed_can_see?("Organization", source)
          elsif source.is_a?(::Business)
            permission.typed_can_see?("Enterprise", source)
          else
            false
          end
        end
      end

      implements_node templates: [[:rrs, :source_type, :source_id, :id]], as: "RRS", ready_date: Platform::Helpers::GlobalId::COHORT_5 do |ruleset|
        { prefix: :rrs, source_type: ruleset.source_type, source_id: ruleset.source_id, id: ruleset.id }
      end

      field :name, String,
        description: "Name of the ruleset.",
        null: false

      field :target, Enums::RepositoryRulesetTarget,
        description: "Target of the ruleset.",
        null: true

      field :source, Unions::RuleSource,
        description: "Source of ruleset.",
        null: false

      field :rules,
        Connections.define(Objects::RepositoryRule),
        description: "List of rules.",
        null: true,
        connection: true do

        T.bind(self, GraphQL::Schema::Member::HasArguments)
        argument :type, Enums::RepositoryRuleType, "The type of rule.", required: false
      end

      def rules(type: nil)
        rules = if type
          @object.rule_configurations.where(rule_type: type).scoped
        else
          @object.rule_configurations.scoped
        end
        @object.async_source.then do |source|
          filtered_rules = rules.filter do |rule|
            impl = RuleEngine::Evaluator.rule_impl_for_rule_type(rule.rule_type)
            # This prevents returning data that is not ready for public consumption
            impl&.publish_api || (impl&.feature_flag.present? && source&.feature_enabled_for_source?(impl&.feature_flag) && @context[:feature_flags].include?(impl&.feature_flag))
          end
          ArrayWrapper.new(filtered_rules)
        end
      end

      field :conditions, Objects::RepositoryRules::RepositoryRuleConditions,
        description: "The set of conditions that must evaluate to true for this ruleset to apply",
        null: false

      def conditions
        Platform::Models::RepositoryRuleConditions.new(@object)
      end

      field :enforcement, Enums::RuleEnforcement,
        description: "The enforcement level of this ruleset",
        null: false

      field :bypass_actors, Connections.define(Objects::RepositoryRulesetBypassActor),
        description: "The actors that can bypass this ruleset",
        null: true,
        connection: true

      database_id_field
      created_at_field
      updated_at_field
    end
  end
end
