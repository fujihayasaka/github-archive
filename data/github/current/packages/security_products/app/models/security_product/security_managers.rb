# typed: true
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityProduct
  class SecurityManagers
    include GitHub::SecurityCenter::LoggingHelper

    def initialize(organization)
      raise ArgumentError, "subject must be an Organization" unless organization.is_a?(Organization)
      @org = organization
    end

    # Public: Returns the IDs of the organization's security manager teams.
    # Does not include descendants that inherited the role from an ancestor team.
    #
    # Returns an Array of Integers
    def team_ids
      UserRole.where(
        actor_type: Team.user_role_target_type,
        role: Role.security_manager_role,
        target_id: @org.id,
        target_type: @org.user_role_target_type
      ).pluck(:actor_id)
    end

    # Public: Returns the organization's security manager teams.
    # Does not include descendants that inherited the role from an ancestor team.
    #
    # Returns an Array of Team
    def teams
      @org.teams.where(id: team_ids)
    end

    # Public: Returns the organization's security manager teams visible to the user.
    # Does not check whether the user has permissions to view the security managers for the org.
    #
    # Returns an Array of Team
    def teams_visible_to(user)
      visible_teams_promises = teams.map do |team|
        team.async_visible_to?(user).then do |is_visible|
          is_visible ? team : nil
        end
      end

      Promise.all(visible_teams_promises).sync.compact
    end

    # Public: Returns the users who are security managers for the organization.
    #
    # Returns an Array of User
    def users
      users = teams.flat_map(&:members)
      users += directly_assigned_users
      users.uniq
    end

    def directly_assigned_user_ids
      UserRole.where(
        actor_type: User.user_role_target_type,
        role: Role.security_manager_role,
        target_id: @org.id,
        target_type: @org.user_role_target_type
      ).pluck(:actor_id)
    end

    def directly_assigned_users
      @org.members.where(id: directly_assigned_user_ids)
    end

    instrument_method \
      :team_ids,
      :teams,
      :teams_visible_to,
      :users,
      :directly_assigned_user_ids,

      :directly_assigned_users
  end
end
