# typed: strict
# frozen_string_literal: true

module Permissions
  module Granters
    class EnterpriseRoleGranter
      NOT_A_MEMBER = "NOT_A_MEMBER"

      class << self
        # Public: Assigns an enterprise role to an actor with proper business logic enforcement
        #
        # actor - A User or BusinessTeam to grant the role to
        # target - A Business (enterprise) to grant the role on
        # role - An EnterpriseRole to be granted
        #
        # Returns a RoleGrantResult
        # Raises GrantFailure if granting was not successful
        sig do
          params(
            actor: T.any(User, BusinessTeam),
            target: Business,
            role: EnterpriseRole,
          ).returns(RoleGrantResult)
        end
        def grant_role(actor:, target:, role:)
          if (actor.is_a?(User) && !target.unaffiliated_member?(actor)) ||
             (actor.is_a?(BusinessTeam) && actor.business != target)
            return Permissions::Granters::RoleGrantResult.failure!(reason: NOT_A_MEMBER)
          end

          if role.enterprise_security_manager?
            return RoleGrantResult.new(
              success: false,
              reason: "Enterprise Security Manager is not enabled for this enterprise.",
            ) unless target.erp_feature_enabled?(:enterprise_teams_esm)

            return RoleGrantResult.new(
              success: false,
              reason: "The Enterprise Security Manager role can only be assigned to an enterprise team.",
            ) unless actor.is_a?(BusinessTeam)

            return RoleGrantResult.new(
              success: false,
              reason: "The number of organizations exceeds the team limit for this enterprise.",
            ) if target.organizations.count > target.business_team_organization_assignment_limit

            ensure_team_assigned_to_all_orgs!(actor)

            role_grant_result = Role.transaction do
              RoleGranter.new(
                actor: actor,
                target: target,
                role: Role.security_manager_role,
                conditions: UserRoleCondition.new(target: UserRoleCondition::Target::AllOrgs),
              ).grant_unless_exists!

              RoleGranter.new(actor: actor, target: target, role: role).grant_unless_exists!
            end

            return role_grant_result
          end

          RoleGranter.new(actor: actor, target: target, role: role).grant_unless_exists!
        rescue RoleGranter::GrantFailure => e
          RoleGrantResult.new(success: false, reason: e.message)
        end

        sig do
          params(
            actor: T.any(User, BusinessTeam),
            target: Business,
            role: EnterpriseRole,
          ).returns(RoleGrantResult)
        end
        def revoke_role(actor:, target:, role:)
          Role.transaction do
            RoleGranter.new(
              actor: actor,
              target: target,
              role: Role.security_manager_role,
            ).revoke_if_exists! if role.enterprise_security_manager?

            RoleGranter.new(actor: actor, target: target, role: role).revoke_if_exists!
          end
        rescue RoleGranter::GrantFailure => e
          RoleGrantResult.new(success: false, reason: e.message)
        end

        private

        # Private: Ensures business team is assigned to all organizations
        #
        # actor - The BusinessTeam actor
        #
        # Returns nothing
        # Raises GrantFailure if the update fails
        sig { params(actor: BusinessTeam).returns(T.nilable(RoleGrantResult)) }
        def ensure_team_assigned_to_all_orgs!(actor)
          return if actor.org_assignment_all?

          unless actor.update(organization_selection_type: :all)
            raise RoleGranter::GrantFailure.new("Failed to update team organization selection to 'all'")
          end
        end
      end
    end
  end
end
