# typed: true
# frozen_string_literal: true

module SecurityProduct
  class SecurityManagerRole
    private_class_method :new

    class << self
      # Public: Does the team have the security manager role granted directly to it?
      # (i.e. not inherited from a parent team)
      #
      # Returns a Boolean
      def granted?(team)
        raise ArgumentError, "subject must be a team" unless team.is_a?(Team) || team.is_a?(Stafftools::Team)

        # Stafftools::Team is a SimpleDelegator around Team. Sorbet doesn't know this, but also won't
        # let us force the cast. Adding sig does not help as there is no inheritance.
        team = T.unsafe(team)

        UserRole.where(
          actor: team,
          role: Role.security_manager_role,
          target_id: team.organization.id,
          target_type: team.organization.user_role_target_type
        ).exists?
      end

      # Public: Filter an array teams for ones that have the security manager role granted directly to them.
      #
      # Returns an array of teams that have the security manager role granted directly to them.
      def filter_granted(teams)
        teams = Array.wrap(teams)
        team_ids = []
        organization_ids = []
        teams.each do |team|
          raise ArgumentError, "subjects must be a team" unless team.is_a?(Team)
          team_ids << team.id
          organization_ids << team.organization_id
        end

        team_ids_with_role = UserRole.where(
          actor_id: team_ids,
          role: Role.security_manager_role,
          target_id: organization_ids,
          target_type: Organization.user_role_target_type
        ).select(:actor_id).each_with_object({}) do |user_role, hash|
          hash[user_role.actor_id] = true
        end

        teams.filter { |t| team_ids_with_role[t.id] }
      end

      # Public: Does the team have the security manager role, either directly or inherited from a parent team?
      #
      # Returns a Boolean
      def granted_or_inherited?(team)
        return true if granted? team
        team.parent_team && granted_or_inherited?(team.parent_team)
      end

      # Public: Adds the provided team to the organization's security managers.
      # Also queues a job to add all of the organization's repositories to the team.
      # If the provided team was already a security manager for the organization, this method does nothing.
      #
      # Raises GrantFailure if granting was not successful.
      def grant!(team)
        unless granted? team
          role_granter(team).grant!
          instrument_event("org.add_security_manager", team: team)
        end
      end

      # Public: Removes the provided team from the organization's security managers.
      # If the provided team isn't a security manager, this method does nothing.
      #
      # Raises GrantFailure if revoking was not successful.
      def revoke!(team, caller: :user)
        raise ArgumentError, "subject must be a team" unless team.is_a?(Team) || team.is_a?(Stafftools::Team)
        raise ArgumentError, "subject must not be enterprise team managed" if team.enterprise_team_managed? && caller != :enterprise_team
        role_granter(team).revoke_if_exists!
        instrument_event("org.remove_security_manager", team: team)
      end

      private

      def role_granter(team)
        ::Permissions::Granters::RoleGranter.new(
          actor: team,
          target: team.organization,
          role: Role.security_manager_role
        )
      end

      def instrument_event(event, team:)
        payload = {
          org: team.organization,
          org_id: team.organization.id,
          team: team,
          team_id: team.id,
        }

        GitHub.instrument(event, payload)
      end
    end
  end
end
