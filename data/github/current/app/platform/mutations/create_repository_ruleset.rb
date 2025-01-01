# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateRepositoryRuleset < Platform::Mutations::Base
      description "Create a repository ruleset"

      minimum_accepted_scopes ["public_repo", "admin:org"]

      argument :source_id, ID, "The global relay id of the source in which a new ruleset should be created in.", required: true, loads: Unions::RuleSource
      argument :name, String, "The name of the ruleset.", required: true
      argument :target, Enums::RepositoryRulesetTarget, "The target of the ruleset.", required: false
      argument :rules, [Inputs::RepositoryRuleInput], "The list of rules for this ruleset", required: false
      argument :conditions, Inputs::RepositoryRules::RepositoryRuleConditionsInput, "The set of conditions for this ruleset", required: true
      argument :enforcement, Enums::RuleEnforcement, "The enforcement level for this ruleset", required: true
      argument :bypass_actors, [Inputs::RepositoryRulesetBypassActorInput], "A list of actors that are allowed to bypass rules in this ruleset.", required: false

      field :ruleset, Objects::RepositoryRuleset, "The newly created Ruleset.", null: true

      include Shared::ModifyRepositoryRuleset

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, source:, **inputs)
        if source.is_a?(::Repository)
          permission.async_owner_if_org(source).then do |org|
            permission.access_allowed? :update_repository_rulesets, resource: source, current_repo: source, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true
          end
        elsif source.is_a?(::Organization)
          permission.access_allowed?(:manage_organization_ref_rules, resource: source, current_repo: nil, current_org: source, allow_integrations: true, allow_user_via_granular_actor: true)
        else
          false
        end
      end

      def resolve(source:, **inputs)
        ensure_source_writable!(source, context:, operation: :creating)

        ruleset = source.rulesets.build

        if RepositoryRuleset.limit_reached?(source)
          raise Errors::Unprocessable.new("The ruleset limit has been reached.")
        end

        update_repository_ruleset(ruleset, inputs, context, operation: "create_repository_ruleset")
      end
    end
  end
end
