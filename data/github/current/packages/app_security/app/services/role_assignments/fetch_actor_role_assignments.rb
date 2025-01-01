# typed: strict
# frozen_string_literal: true

module RoleAssignments
  class FetchActorRoleAssignments
    include GitHub::Memoizer

    sig { returns(BusinessTeam) }
    attr_reader :actor

    sig { params(actor: BusinessTeam).void }
    def initialize(actor:)
      @actor = actor
    end

    DISTRIBUTION_TIME_STAT = T.let("role_assignments.fetch_actor_role_assignments".freeze, String)

    # for now, only supports directly-assigned roles
    sig { returns(Types::ActorRoleAssignment) }
    def enterprise_role_assignments
      GitHub.dogstats.distribution_time(DISTRIBUTION_TIME_STAT, tags: ["method:enterprise_role_assignments"]) do
        GitHub.tracer.in_span("RoleAssignments::FetchActorRoleAssignments#enterprise_role_assignments") do
          return Types::ActorRoleAssignment.new(
            actor: Types::Actor.from_model(actor),
            role_assignments: [],
          ) unless business_teams_enabled

          role_assignments = all_roles.filter_map do |ur|
            next unless (role = available_roles[ur.role_id])
            next if role.is_delegate

            #  If the role has a delegate role, we need to check if the delegate role grants access to organizations
            org_access = nil
            if role.delegate_role_id &&
                (delegate_user_role = all_roles.find { |ur| ur.role_id == role.delegate_role_id })

              conditions_target = delegate_user_role.conditions_target

              org_access = if conditions_target == UserRoleCondition::Target::AllOrgs.serialize
                Types::OrgAccess.new(
                  target: conditions_target,
                )
              elsif conditions_target == UserRoleCondition::Target::SomeOrgs.serialize
                Types::OrgAccess.new(
                  target: conditions_target,
                  selected_count: delegate_user_role.conditions_target_ids&.size || 0,
                  total_count: organization_count,
                  limit: business.business_team_organization_assignment_limit,
                )
              end
            end

            Types::RoleAssignment.new(
              role: role,
              directly_assigned: true,
              indirect_assignments: [], # Business teams can't be nested yet, thus have no indirect assignments
              org_access: org_access
            )
          end

          Types::ActorRoleAssignment.new(
            actor: Types::Actor.from_model(actor),
            role_assignments:,
          )
        end
      end
    end

    sig { returns(Integer) }
    def total_role_assignments
      all_roles.filter_map do |ur|
        role = available_roles[ur.role_id]
        role unless role&.is_delegate
      end.size
    end

    sig { returns(T::Boolean) }
    def is_enterprise_security_manager?
      role = available_roles[EnterpriseRole.enterprise_security_manager_role.id]
      role.present? && all_roles.exists?(role_id: role.id)
    end

    private

    sig { returns(Business) }
    memoize def business
      T.must(actor.business)
    end

    sig { returns(Integer) }
    memoize def organization_count
      business.organizations.count
    end

    sig { returns(T::Hash[Integer, Types::Role]) }
    memoize def available_roles
      assignable_roles = business.roles_assignable_to_target
      include_delegate = business.erp_feature_enabled?(:enterprise_teams_esm)

      Types::Role.from_enterprise_roles(
        assignable_roles,
        include_delegate:,
        with_fgps: true,
      ).index_by(&:id)
    end

    sig { returns(ActiveRecord::Relation) }
    def all_roles
      UserRole
        .select(:actor_id, :actor_type, :role_id, :conditions_target, :conditions_target_ids)
        .where(
          role_id: available_roles.keys,
          target_type: "Business",
          target_id: business.id,
          actor_type: actor.class,
          actor_id: actor.id,
        )
        .order(:role_id)
    end

    sig { returns(T::Boolean) }
    def business_teams_enabled
      T.must(@actor.business).erp_feature_enabled?(:enterprise_teams_crud)
    end
  end
end
