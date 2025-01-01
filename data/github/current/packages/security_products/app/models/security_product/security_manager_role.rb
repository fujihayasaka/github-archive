# typed: strict
# frozen_string_literal: true

module SecurityProduct
  class SecurityManagerRole
    private_class_method :new

    class << self
      # Public: Does the team have the security manager role granted directly to it?
      # (i.e. not inherited from a team or parent team)
      #
      # Returns a Boolean
      sig { params(team: Team).returns(T::Boolean) }
      def granted_to_team?(team)
        granted? team, target: T.must(team.organization)
      end

      # Public: Does the actor have the security manager role granted directly to it for the given org?
      # (i.e. not inherited from a team or parent team)
      #
      # Returns a Boolean
      sig { params(actor: T.any(User, Team), target: Organization).returns(T::Boolean) }
      def granted?(actor, target:)
        raise ArgumentError, "Subject must be a team or vanilla user. Got: #{actor.class}" unless actor.is_a?(Team) || actor.user?

        UserRole.where(
          actor:,
          role: Role.security_manager_role,
          target_id: target.id,
          target_type: target.user_role_target_type
        ).exists?
      end

      # Public: Filter an array teams for ones that have the security manager role granted directly to them.
      #
      # Returns an array of teams that have the security manager role granted directly to them.
      sig { params(teams: T.any(Team, T::Array[Team])).returns(T::Array[Team]) }
      def filter_granted(teams)
        teams = Array.wrap(teams)
        raise ArgumentError, "teams must all be Team objects" unless teams.all? { |team| team.is_a?(Team) }

        team_ids_with_role = UserRole \
          .where(
            actor: teams,
            role: Role.security_manager_role,
            target_id: teams.map(&:organization_id).uniq,
            target_type: Organization.user_role_target_type,
          )
          .pluck(:actor_id)
          .each_with_object({}) { |team_id, hash| hash[team_id] = true }

        teams.filter { |t| team_ids_with_role[t.id] }
      end

      # Public: Does the team have the security manager role, either directly or inherited from a parent team?
      #
      # Returns a Boolean
      sig { params(team: Team).returns(T::Boolean) }
      def granted_to_team_or_inherited?(team)
        return true if granted_to_team? team
        !!(team.parent_team && granted_to_team_or_inherited?(team.parent_team))
      end

      # Public: Adds the provided team to the organization's security managers.
      # Also queues a job to add all of the organization's repositories to the team.
      # If the provided team was already a security manager for the organization, this method does nothing.
      #
      # Raises GrantFailure if granting was not successful.
      sig { params(team: Team).void }
      def grant_to_team!(team)
        unless granted_to_team? team
          role_granter(team).grant!
          instrument_event("org.add_security_manager", team:)
        end
      end

      # Public: Removes the provided team from the organization's security managers.
      # If the provided team isn't a security manager, this method does nothing.
      #
      # Raises GrantFailure if revoking was not successful.
      sig { params(team: Team, caller: Symbol).void }
      def revoke_from_team!(team, caller: :user)
        raise ArgumentError, "subject must not be enterprise team managed" if team.enterprise_team_managed? && caller != :enterprise_team
        role_granter(team).revoke_if_exists!
        instrument_event("org.remove_security_manager", team:)
      end

      private

      sig { params(team: Team).returns(::Permissions::Granters::RoleGranter) }
      def role_granter(team)
        ::Permissions::Granters::RoleGranter.new(
          actor: team,
          target: team.organization,
          role: Role.security_manager_role,
        )
      end

      sig { params(event: String, team: Team).void }
      def instrument_event(event, team:)
        payload = {
          org: team.organization,
          org_id: team.organization&.id,
          team:,
          team_id: team.id,
        }

        GitHub.instrument(event, payload)
      end
    end
  end
end
