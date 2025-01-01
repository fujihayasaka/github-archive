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

        GitHub.dogstats.distribution_time("security_center.business_authz_enumeration.dist", tags: ["method:#{__method__}"]) do
          Ability
            .organization_memberships_for_user(actor_id: @actor.id)
            .batched_scope(:subject_id, values: business_org_ids, batch_size: BATCH_SIZE)
            .execute { |scope| scope.async_pluck(:action, :subject_id) }
            .flat_map(&:value)
            .group_by(&:first)
            .symbolize_keys
            .transform_values { |v| v.map(&:second) }
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
        # Fetch the role assignments that have the given actions as all-repo FGPs on the business' organizations
        actions_from_role_assignments = GitHub.dogstats.distribution_time("security_center.business_authz_enumeration.dist", tags: ["method:#{__method__}", "step:fetch_role_assignments"]) do
          @actions.flat_map do |action|
            log_timing(step: "Fetch role assignments", "gh.security_center.org_ids.size": business_org_ids_where_member.size, "gh.security_center.authz.action": action) do
              role_ids_with_action_rel = Role
                .joins("INNER JOIN role_permissions ON roles.id = role_permissions.role_id")
                .where(role_permissions: { action: })
                .select(:id)
              role_ids_with_action_from_base_role_rel = Role
                .joins("INNER JOIN role_permissions ON roles.base_role_id = role_permissions.role_id")
                .where(role_permissions: { action: })
                .select(:id)
              role_ids_subquery_sql = [
                role_ids_with_action_rel,
                role_ids_with_action_from_base_role_rel,
              ].map(&:to_sql).join(" UNION ")

              T.let(
                UserRole
                  .where("role_id IN (#{role_ids_subquery_sql})")
                  .where(target_type: "Organization")
                  .batched_scope(:target_id, values: business_org_ids_where_member, batch_size: BATCH_SIZE)
                  .execute { |scope| scope.async_pluck(:target_id, :actor_id, :actor_type) }
                  .flat_map(&:value)
                  .each { |result| result.unshift(action) },
                T::Array[[String, Integer, Integer, String]],
              )
            end
          end
        end

        # Fetch the teams that the user is on from the teams that have role assignments on the business' organizations
        team_ids = actions_from_role_assignments.filter_map { |_action, _org_id, actor_id, actor_type| actor_id if actor_type == "Team" }
        is_actor_a_member_by_team_id = GitHub.dogstats.distribution_time("security_center.business_authz_enumeration.dist", tags: ["method:#{__method__}", "step:fetch_teams"]) do
          log_timing(step: "Fetch actor's teams", "gh.security_center.team_ids.size": team_ids.size) do
            T.let(
              Ability
                .where(
                  subject_type: "Team",
                  subject_id: team_ids,
                  actor_type: "User",
                  actor_id: @actor.id,
                )
                .where("priority <= ?", Ability.priorities[:direct])
                .distinct
                .pluck(:subject_id)
                .each_with_object(Hash.new(false)) { |team_id, hash| hash[team_id] = true },
              T::Hash[Integer, T::Boolean],
            )
          end
        end

        # Filter the permissions to only the ones that the user has
        actions_for_actor = actions_from_role_assignments.filter_map do |action, org_id, actor_id, actor_type|
          next unless actor_type == "User" || actor_type == "Team"
          next if actor_type == "User" && actor_id != @actor.id
          next if actor_type == "Team" && !is_actor_a_member_by_team_id[actor_id]
          [action.to_sym, org_id]
        end

        # Fetch the permissions implicitly granted to the user by an organization's default repository role.
        # At the time of this writing an organization's default repository role can only be one of the primary system roles: :read, :write, or :admin.
        system_roles = system_roles_to_actions.keys.sort!
        actions_from_implicit_roles = GitHub.dogstats.distribution_time("security_center.business_authz_enumeration.dist", tags: ["method:#{__method__}", "step:fetch_implicit_permissions"]) do
          log_timing(step: "Fetch implicit permissions from default repository role organization setting", "gh.security_center.roles": system_roles, "gh.security_center.org_ids.size": business_org_ids_where_member.size) do
            T.let(
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

        # Transform [["action", org_id], ...] into { action: [org_id, ...], ... }
        (actions_for_actor + actions_from_implicit_roles)
          .group_by(&:first)
          .transform_values! { |v| v.map(&:second).uniq }
          .tap { |h| @actions.each { |action| h[action] ||= [] } } # ensure each action has a value
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
