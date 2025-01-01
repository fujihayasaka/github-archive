# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityProduct
  module Permissions
    class BusinessAuthzEnumerator
      include GitHub::Memoizer
      include GitHub::SecurityCenter::LoggingHelper

      BATCH_SIZE = 5_000
      private_constant :BATCH_SIZE

      sig do
        params(
          actor: User,
          business: Business,
          cap_filter: ::ConditionalAccess::Filter,
          actions: T.nilable(T.any(Symbol, T::Array[Symbol]))
        ).void
      end
      def initialize(actor:, business:, cap_filter:, actions: nil)
        raise ArgumentError, "actor must be a vanilla User" unless actor.user?
        raise ArgumentError, "actions must have at least one value" if actions&.empty?

        @actor = actor
        @business = business
        @actions = T.let(Array.wrap(actions), T::Array[Symbol])
        @cap_filter = cap_filter
      end

      sig { returns(T::Array[::Organization]) }
      memoize def authorized_orgs_where_actor_has_membership
        @cap_filter.authorized_resources(candidate_orgs_where_actor_has_membership)
      end

      sig { returns(T::Array[::Organization]) }
      memoize def unauthorized_orgs_where_actor_has_membership
        @cap_filter.unauthorized_resources(candidate_orgs_where_actor_has_membership)
      end

      sig { returns(T::Hash[Symbol, T::Array[::Organization]]) }
      memoize def authorized_orgs_by_action
        result = Hash.new { raise ArgumentError.new("Attempted to access authorized orgs hash with unevaluated action") }
        return result if @actions.blank?

        authorized_orgs_by_id = T.let(
          @cap_filter.authorized_resources(candidate_orgs_for_actions).index_by(&:id),
          T::Hash[Integer, ::Organization],
        )
        @actions.each_with_object(T.let(result, T::Hash[Symbol, T::Array[::Organization]])) do |action, hash|
          all_repo_fgp_org_ids = T.must_because(business_org_ids_where_member_by_action[action]) { "hash should have a value for all actions" }
          # Assume being an org owner is enough to grant any action on the org
          org_ids = authorized_orgs_by_id.keys & (business_org_ids_where_owner | all_repo_fgp_org_ids)
          hash[action] = org_ids.map { |id| T.must_because(authorized_orgs_by_id[id]) { "key should come from a subset of authorized orgs" } }
        end
      end

      sig { returns(T::Array[::Organization]) }
      memoize def unauthorized_orgs_for_actions
        return [] if @actions.blank?
        @cap_filter.unauthorized_resources(candidate_orgs_for_actions)
      end

      private

      sig { returns(T::Hash[Symbol, T::Array[Integer]]) }
      memoize def business_org_memberships_by_role
        business_org_ids = @business.organization_ids
        use_indirect_abilities = @business.erp_feature_enabled?(:enterprise_teams_org_assignment)

        GitHub.dogstats.distribution_time("security_center.business_authz_enumeration.dist", tags: ["method:#{__method__}"]) do
          roles = Ability
            .direct_organization_memberships_for_user(actor_id: @actor.id)
            .batched_scope(:subject_id, values: business_org_ids, batch_size: BATCH_SIZE)
            .execute { |scope| scope.async_pluck(:action, :subject_id) }
            .flat_map(&:value)
            .group_by(&:first)
            .symbolize_keys
            .transform_values { |v| v.map(&:second) }

          if use_indirect_abilities
            roles[:read] ||= []
            roles[:read] |= Ability.organization_memberships_for_user(user_id: @actor.id)
          end

          roles
        end
      end

      sig { returns(T::Array[Integer]) }
      def business_org_ids_where_owner
        business_org_memberships_by_role[:admin] || []
      end

      sig { returns(T::Array[Integer]) }
      def business_org_ids_where_member
        # We don't need to check for :write because there's only :admin -> owner and :read -> member
        business_org_memberships_by_role[:read] || []
      end

      sig { returns(T::Array[::Organization]) }
      memoize def candidate_orgs_where_actor_has_membership
        candidate_org_ids = business_org_memberships_by_role.values.flatten

        GitHub.dogstats.distribution_time("security_center.business_authz_enumeration.dist", tags: ["method:#{__method__}"]) do
          ::Organization
            .batched_scope(:id, values: candidate_org_ids, batch_size: BATCH_SIZE)
            .execute(&:load_async)
        end
      end

      sig { returns(T::Hash[String, T::Array[Symbol]]) }
      memoize def system_roles_to_actions
        GitHub.dogstats.distribution_time("security_center.business_authz_enumeration.dist", tags: ["method:#{__method__}"]) do
          Role
            .primary_system_repo_roles
            .joins(:permissions)
            .where(permissions: { action: @actions })
            .pluck(:action, :name)
            .group_by(&:second)
            .transform_values { |v| v.map { |action, _| action.to_sym } }
        end
      end

      sig { returns(T::Hash[Symbol, T::Array[Integer]]) }
      memoize def business_org_ids_where_member_by_action
        # first we fetch the permissions for the actor on the business' organizations
        action_to_org_for_actor = Authz.domain.user_roles.actors_permissions_for_orgs(
          target_ids: business_org_ids_where_member,
          actions: @actions,
          actor_type: "User",
          actor_id: [@actor.id]
        )

        out = T.let(
          action_to_org_for_actor
            .group_by { |action, _org_id| T.cast(action, String).to_sym }
            .transform_values { |pairs| pairs.map { |_action, org_id| T.cast(org_id, Integer) } },
          T::Hash[Symbol, T::Array[Integer]]
        )

        # Then we fetch the permissions for all teams which have role assignments on the business' organizations
        teams_with_org_permissions = Authz.domain.user_roles.get_permissible_team_roles_for_organizations(
          organization_ids: business_org_ids_where_member,
          actions: @actions,
          business_id: @business.id,
        )

        # Query Ability with tuple-style IN clause to check if user is member of any teams
        user_team_memberships = if teams_with_org_permissions.any?

          team_type_id_pairs = teams_with_org_permissions.values.flatten(1).map do |team_data|
            [team_data[0], team_data[1]] # [actor_type, actor_id]
          end

          # team type, team id pairs
          tuple_conditions = team_type_id_pairs.uniq.map { |type, id| "('#{type}', #{id})" }.join(", ")

          Ability
            .where(actor_type: "User", actor_id: @actor.id)
            .where("(subject_type, subject_id) IN (#{tuple_conditions})") # (subject_type, subject_id) IN (('Team', 123), ('BusinessTeam', 456), ...)
            .where("priority <= ?", Ability.priorities[:direct])
            .distinct
            .pluck(:subject_type, :subject_id)
            .to_set
        else
          Set.new
        end

        # Process team permissions for teams where the user is a member
        teams_with_org_permissions.each do |org_id, team_permissions|
          team_permissions.each do |actor_type, actor_id, action|
            if user_team_memberships.include?([actor_type, actor_id])
              action_sym = T.cast(action, Symbol)
              out[action_sym] ||= []
              T.must(out[action_sym]) << org_id
            end
          end
        end

        # Merge implicit roles into the out hash
        actions_from_implicit_org_roles.each do |action, org_id|
          out[action] ||= []
          T.must(out[action]) << org_id
        end

        # Ensure each action has a value (empty array if no permissions found)
        @actions.each { |action| out[action] ||= [] }

        out

      end

      sig { returns(T::Array[::Organization]) }
      memoize def candidate_orgs_for_actions
        candidate_org_ids = (business_org_ids_where_owner | business_org_ids_where_member_by_action.values.flatten)

        GitHub.dogstats.distribution_time("security_center.business_authz_enumeration.dist", tags: ["method:#{__method__}"]) do
          ::Organization
            .batched_scope(:id, values: candidate_org_ids, batch_size: BATCH_SIZE)
            .execute(&:load_async)
        end
      end

      # Fetch the permissions implicitly granted to the user by an organization's default repository role.
      # At the time of this writing an organization's default repository role can only be one of the primary system roles: :read, :write, or :admin.
      sig { returns(T::Array[[Symbol, Integer]]) }
      def actions_from_implicit_org_roles

        system_roles = system_roles_to_actions.keys.sort!
        GitHub.dogstats.distribution_time("security_center.business_authz_enumeration.dist", tags: ["method:#{__method__}", "step:fetch_implicit_permissions"]) do
          log_timing(step: "Fetch implicit permissions from default repository role organization setting", "gh.security_center.roles": system_roles, "gh.security_center.org_ids.size": business_org_ids_where_member.size) do
            out = T.let(
              Ability
                .where(
                  actor_type: "Organization",
                  actor_id: business_org_ids_where_member,
                  action: system_roles,
                  subject_type: "Repository",
                )
                .distinct
                .pluck(:action, :actor_id)
                .flat_map do |system_role, org_id|
                  # Transform ["write", org_id] into [[:read_code_scanning, org_id], [:view_dependabot_alerts, org_id], ...]
                  actions = T.must(system_roles_to_actions[system_role])
                  actions.map { |action| [action, org_id] }
                end,
              T::Array[[Symbol, Integer]],
            )
          end
        end
      end

      instrument_method \
        :authorized_orgs_by_action,
        :authorized_orgs_where_actor_has_membership,
        :business_org_ids_where_member_by_action,
        :business_org_ids_where_member,
        :business_org_ids_where_owner,
        :business_org_memberships_by_role,
        :candidate_orgs_for_actions,
        :candidate_orgs_where_actor_has_membership,
        :system_roles_to_actions,
        :unauthorized_orgs_for_actions,
        :unauthorized_orgs_where_actor_has_membership
    end
  end
end
