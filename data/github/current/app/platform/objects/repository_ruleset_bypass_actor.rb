# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryRulesetBypassActor < Platform::Objects::Base
      description "A team or app that has the ability to bypass a rules defined on a ruleset"
      minimum_accepted_scopes ["public_repo"]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, rule)
        rule.async_repository_ruleset.then do |ruleset|
          ruleset.async_source.then do |source|
            if source.is_a?(::Repository)
              source.async_can_edit_repo_protections?(permission.viewer)
            elsif source.is_a?(::Organization)
              source.can_manage_organization_ref_rules?(permission.viewer)
            elsif source.is_a?(::Business)
              permission.access_allowed?(:administer_business, resource: source, repo: nil, organization: nil, allow_integrations: true, allow_user_via_granular_actor: true)
            else
              false
            end
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, rule)
        rule.async_repository_ruleset.then do |ruleset|
          ruleset.async_source.then do |source|
            if source.is_a?(::Repository)
              source.async_can_edit_repo_protections?(permission.viewer)
            elsif source.is_a?(::Organization)
              source.can_manage_organization_ref_rules?(permission.viewer)
            elsif source.is_a?(::Business)
              permission.access_allowed?(:administer_business, resource: source, repo: nil, organization: nil, allow_integrations: true, allow_user_via_granular_actor: true)
            else
              false
            end
          end
        end
      end

      implements_node templates: [[:rrba, :ruleset_id, :id]], as: "RRBA", ready_date: Platform::Helpers::GlobalId::COHORT_5 do |bypass_actor|
        { prefix: :rrba, ruleset_id: bypass_actor.repository_ruleset_id, id: bypass_actor.id }
      end

      field :actor, Unions::BypassActor,
        description: "The actor that can bypass rules.",
        null: true

      def actor
        return nil if @object.try(:organization_admin) || @object.actor_type == "RepositoryRole" || @object.try(:deploy_key) || @object.try(:enterprise_owner)

        @object.async_actor.then do |actor|
          actor.is_a?(::IntegrationInstallation) ? actor.async_integration : actor
        end
      end

      field :repository_role_name, String,
        description: "If the actor is a repository role, the repository role's name that can bypass",
        null: true

      def repository_role_name
        if @object.actor_type == "RepositoryRole"
          @object.async_actor.then do |actor|
            actor.name
          end
        end
      end

      field :repository_role_database_id, Integer,
        description: "If the actor is a repository role, the repository role's ID that can bypass",
        null: true

      def repository_role_database_id
        if @object.actor_type == "RepositoryRole"
          @object.async_actor.then do |actor|
            actor.id
          end
        end
      end

      field :organization_admin, Boolean,
        description: "This actor represents the ability for an organization owner to bypass",
        null: false

      def organization_admin
        @object.try(:organization_admin) || false
      end

      field :enterprise_owner, Boolean,
        description: "This actor represents the ability for an enterprise owner to bypass",
        null: false

      def enterprise_owner
        @object&.actor_type == "EnterpriseOwner"
      end

      field :deploy_key, Boolean,
        description: "This actor represents the ability for a deploy key to bypass",
        null: false

      def deploy_key
        @object.try(:deploy_key) || false
      end

      field :bypass_mode, Enums::RepositoryRulesetBypassActorBypassMode,
        description: "The mode for the bypass actor",
        null: true

      field :repository_ruleset, RepositoryRuleset,
        description: "Identifies the ruleset associated with the allowed actor",
        null: true
    end
  end
end
