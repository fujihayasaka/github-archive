# typed: true
# frozen_string_literal: true

class Team
  # These methods are related to the various team roles. Those roles are:
  #
  # member     - Represented by having a direct :read ability on the team.
  # maintainer - Represented by having a direct :admin ability on the team. Can
  #              admin the team despite being a non-admin org member.
  module Roles
    extend T::Helpers
    requires_ancestor { Team }
    class MemberRequiredError < StandardError
      def initialize(team, user)
        super "#{user.login} isn't a member of the team #{team.id}"
      end
    end

    class AlreadyOrgAdminError < StandardError
      def initialize(team, user)
        super "#{user.login} is already an admin of team #{team.id}'s org"
      end
    end

    # Public: Is this user an owner of this team?
    # a user is an owner if they are an admin of the organization
    #
    # user - the user to check.
    #
    # Returns a boolean.
    def owner?(user)
      member?(user) && organization&.adminable_by?(user)
    end

    # Public: The list of maintainers of this team.
    #
    # Returns an array of Users.
    def maintainers
      maintainer_ids = Ability.where(
        actor_type: "User",
        subject_id: id,
        subject_type: "Team",
        priority: Ability.priorities[:direct],
        action: Ability.actions[:admin],
      ).pluck(:actor_id)
      User.where(id: maintainer_ids)
    end

    def maintainers_and_owners_sorted_by_login
      members_sorted_by_login - normal_members_sorted_by_login
    end

    # members of team who aren't maintainers or owners
    # owners are members that are admins of the organization
    def normal_members_sorted_by_login
      normal_members = members - maintainers - organization&.admins
      normal_members.sort_by { |u| u.login.downcase }
    end

    # Public: a list of team maintainers sorted by login
    def maintainers_sorted_by_login
      maintainers.sort_by { |u| u.login.downcase }
    end

    # Public: Is this user a maintainer of this team?
    #
    # user - the user to check.
    #
    # Returns a boolean.
    def maintainer?(user)
      Ability.where(
        actor_type: "User",
        actor_id: user.id,
        subject_id: self.id,
        subject_type: "Team",
        action: Ability.actions[:admin],
        priority: Ability.priorities[:direct],
      ).any?
    end

    # Public: Make the user a maintainer of this team. Note that the user must
    # be a member of the team in order to be promoted to a maintainer.
    #
    # user - the user to make a maintainer.
    #
    # Returns the user's Ability on the team.
    def promote_maintainer(user)
      # org admins already have maintainer roles so they do not need to be promoted
      return true if organization&.adminable_by?(user)

      unless member?(user)
        raise MemberRequiredError.new(self, user)
      end

      unless T.unsafe(organization)&.direct_member?(user)
        raise Organization::AbilityDependency::DirectMemberRequiredError.new(organization, user)
      end

      grant(user, :admin)

      instrument :promote_maintainer, {
        user: user
      }
    end

    # Public: Demote the user from being a maintainer back to being a regular
    # member. Like #promote_admin, the user must be a member of the team.
    #
    # user - the user who should no longer be a maintainer.
    # with_posting_ability - boolean; grant or revoke the authzd role for creating team posts
    #
    # Returns the user's Ability on the team.
    def demote_maintainer(user, with_posting_ability: false)
      raise MemberRequiredError.new(self, user) unless member?(user)
      grant(user, :read)

      if with_posting_ability
        ::Permissions::Granters::RoleGranter.new(actor: user, target: self, role: Role.team_writer_role).grant_unless_exists!
      else
        ::Permissions::Granters::RoleGranter.new(actor: user, target: self, role: Role.team_writer_role).revoke_if_exists!
      end

      instrument :demote_maintainer, {
        user: user
      }
    end
  end
end
