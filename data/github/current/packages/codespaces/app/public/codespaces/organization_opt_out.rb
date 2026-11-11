# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class OrganizationOptOut
    class Result
      attr_accessor :removed_users, :status, :removed_teams

      def initialize
        @removed_users = []
        @removed_teams = []
      end

      def add_removed_user(user)
        removed_users << user
      end

      def add_removed_team(team)
        removed_teams << team
      end

      def success!
        @status = :success
      end

      def failure!
        @status = :failure
      end

      def success?
        status == :success
      end
    end

    def enrolled_members
      query = UserRole.includes(:role).where(
        roles: { name: Codespaces::OrgPolicy::CODESPACE_ORG_CREATOR_ROLE },
        target_type: "Organization",
        target_id: organization.id,
        actor_type: "User",
      )
      query = query.where(actor_id: users_ids) if users_ids.any? # scope to users if provided
      member_ids = query.pluck(:actor_id)

      organization.members.where(id: member_ids) + organization.outside_collaborators.where(id: member_ids)
    end

    def self.call(organization:, actor:, users: [], teams: [])
      new(organization: organization, actor: actor, users: users, teams: teams).call
    end

    def initialize(organization:, actor:, access_control: Codespaces::OrgPolicy, users: [], teams: [])
      @organization = organization
      @actor = actor
      @access_control = access_control
      @users_ids = users.pluck(:id)
      @team_ids = teams.pluck(:id)
    end

    def call
      build_result do |result|
        begin
          remove_access_for_all_users(result)
          remove_access_for_all_teams(result)

          suspend_codespaces
          result.success!
        rescue Codespaces::OrgPolicy::RoleGranterError
          result.failure!
        end
      end
    end

    private

    attr_reader :organization, :actor, :access_control, :users_ids, :team_ids

    def build_result(&block)
      result = Result.new
      block.call(result)
      result
    end

    def remove_access_for_all_users(result)
      enrolled_members.each do |member|
        remove_access_for_actor(member)
        result.add_removed_user(member)
        perform_org_settings_job(member) if users_ids.any? # only trigger when revoking certain users
      end
    end

    def remove_access_for_all_teams(result)
      enrolled_teams.each do |team|
        remove_access_for_actor(team)
        result.add_removed_team(team)
        perform_org_settings_job(team) if team_ids.any? # only trigger when revoking certain teams
      end
    end

    def enrolled_teams
      query = UserRole.includes(:role).where(
        roles: { name: Codespaces::OrgPolicy::CODESPACE_ORG_CREATOR_ROLE },
        target_type: "Organization",
        target_id: organization.id,
        actor_type: "Team",
      )
      query = query.where(actor_id: team_ids) if team_ids.any? # scope to users if provided
      actor_ids = query.pluck(:actor_id)

      organization.teams.where(id: actor_ids)
    end

    def remove_access_for_actor(actor)
      access_control.revoke_billing_permission!(actor, organization)
    end

    def codespaces
      query = Codespace.for_organization(organization)
      query = query.where(owner_id: users_ids) if users_ids.any? # scope to users if provided
      query
    end

    def suspend_codespaces
      codespaces.each { ScheduleEnvironmentSuspension.call(_1) }
    end

    def perform_org_settings_job(user)
      Codespaces::OrgSettingsChangedJob.perform_later(
        context: user.id,
        event_type: Codespaces::Events::ORG_CODESPACES_DISABLED_USER,
        actor_id: actor.id
      )
    end
  end
end
