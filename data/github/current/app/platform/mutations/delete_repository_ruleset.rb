# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteRepositoryRuleset < Platform::Mutations::Base
      description "Delete a repository ruleset"

      minimum_accepted_scopes ["public_repo", "admin:org", "admin:enterprise"]

      argument :repository_ruleset_id, ID, "The global relay id of the repository ruleset to be deleted.", required: true, loads: Objects::RepositoryRuleset, as: :ruleset

      include Shared::ModifyRepositoryRuleset

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, ruleset:, **inputs)
        ruleset.async_source.then do |source|
          if source.is_a?(::Repository)
            permission.async_owner_if_org(source).then do |org|
              permission.access_allowed? :update_repository_rulesets, resource: source, current_repo: source, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true
            end
          elsif source.is_a?(::Organization)
            permission.access_allowed?(:manage_organization_ref_rules, resource: source, current_repo: nil, current_org: source, allow_integrations: true, allow_user_via_granular_actor: true)
          elsif source.is_a?(::Business)
            permission.access_allowed?(:administer_business, resource: source, repo: nil, organization: nil, allow_integrations: true, allow_user_via_granular_actor: true)
          else
            false
          end
        end
      end

      def resolve(ruleset:, **inputs)
        ruleset.async_source.then do |source|
          ensure_source_writable!(source, context:, operation: :deleting)

          ruleset.destroy

          {}
        end
      end
    end
  end
end
