
# typed: strict
# frozen_string_literal: true

module Codespaces
  class ProcessOrganizationEnablementChange < Command
    extend T::Sig
    class InvalidEnablementError < StandardError; end
    class UnknownUsersError < StandardError; end
    class UnknownTeamsError < StandardError; end
    class GrantFailedError < StandardError; end
    class RevokeFailedError < StandardError; end

    sig { returns(::Organization) }
    attr_reader :organization

    sig { returns(::User) }
    attr_reader :actor

    sig { returns(String) }
    attr_reader :enablement

    sig { returns(T::Array[String]) }
    attr_reader :users_to_update

    sig { returns(T::Array[String]) }
    attr_reader :teams_to_update

    sig { returns(T::Boolean) }
    attr_reader :limit_updated

    sig { returns(T::Boolean) }
    attr_reader :selected_users_or_teams_updated

    sig { params(organization: ::Organization, actor: ::User, enablement: String, users_to_update: T::Array[String], teams_to_update: T::Array[String]).void }
    def initialize(organization:, actor:, enablement:, users_to_update: [], teams_to_update: [])
      @organization = organization
      @actor = actor
      @enablement = enablement
      @users_to_update = users_to_update
      @teams_to_update = teams_to_update
      @limit_updated = T.let(false, T::Boolean)
      @selected_users_or_teams_updated = T.let(false, T::Boolean)
    end

    sig { override.returns(T.nilable(Codespaces::ProcessOrganizationEnablementChange)) }
    def perform
      return unless organization.present?

      @limit_updated = organization.update_organization_codespaces_user_limit(enablement, actor: actor).present?
      emit_audit_log(:codespaces_access_updated, actor:, enablement:) if limit_updated

      case enablement
      when Configurable::OrganizationCodespacesUserLimit::DISABLED
        process_all_disable
      when Configurable::OrganizationCodespacesUserLimit::ALL_USERS, Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS
        process_all_enable
      when Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS
        # If we are switching from any other setting to selected users we want to act as if the user had disabled codespaces
        # completely first so that we can remove access from any users that were previously being allowed but no longer
        # should be.
        process_all_disable if limit_updated
        user_result = process_selected_enable
        team_result = process_selected_teams_enable
        @selected_users_or_teams_updated = user_result.any? || team_result.any?
      end

      unless enablement == Configurable::OrganizationCodespacesUserLimit::DISABLED
        # Include Codespaces rate plan charges in the Zuora subscription for future charges.
        organization.synchronize_general_purpose_subscription_later
        organization.accept_organization_codespaces_terms(actor: actor)
      end

      self
    end

    private

    sig { void }
    def process_all_disable
      result = Codespaces::OrganizationOptOut.call(organization: organization, actor: actor)
      if !result.success?
        raise RevokeFailedError.new("An error occurred when trying to revoke access, please try again later.")
      end
      Codespaces::OrgSettingsChangedJob.perform_later(context: organization.id, event_type: Codespaces::Events::ORG_CODESPACES_DISABLED, actor_id: actor.id)
    end

    sig { void }
    def process_all_enable
      GlobalInstrumenter.instrument("codespaces.org_enabled", { organization: organization })
      Codespaces::OrgSettingsChangedJob.perform_later(context: organization.id, event_type: Codespaces::Events::ORG_CODESPACES_ENABLED, actor_id: actor.id)
    end

    sig { returns(T::Array[::User]) }
    def process_selected_enable
      users = organization.members.where(login: users_to_update) + organization.outside_collaborators.where(login: users_to_update)

      if users_to_update.any? && users.none?
        # raise error if none of the users are in the org or outside collaborators
        raise UnknownUsersError.new
      end

      existing_user_ids = UserRole.where(
        role: Role.codespace_org_creator_role,
        target_id: organization.id,
        target_type: "Organization"
      ).pluck(:actor_id)

      requested_user_ids = users.pluck(:id)
      user_ids_to_revoke = existing_user_ids - requested_user_ids

      revoke_access_for_users(User.where(id: user_ids_to_revoke)) + grant_access_for_users(users)
    end

    sig { returns(T::Array[::Team]) }
    def process_selected_teams_enable
      teams = organization.teams.where(slug: teams_to_update)

      if teams_to_update.any? && teams.none?
        # raise error if none of the teams are in the org
        raise UnknownTeamsError.new
      end

      # Revoke access to any selected teams

      existing_team_ids = UserRole.where(
        role: Role.codespace_org_creator_role,
        actor_type: "Team",
        target_id: organization.id,
        target_type: "Organization"
      ).pluck(:actor_id)

      requested_team_ids = teams.pluck(:id)
      team_ids_to_revoke = existing_team_ids - requested_team_ids

      revoke_access_for_teams(Team.where(id: team_ids_to_revoke)) + grant_access_for_teams(teams)
    end

    sig { params(users: T::Array[::User]).returns(T::Array[::User]) }
    def grant_access_for_users(users)
      successful_users = []
      failed_users = []

      users.each do |user|
        begin
          has_creator_role = UserRole.find_by(
            actor: user,
            target_id: organization.id,
            target_type: "Organization",
            role: Role.codespace_org_creator_role.id
          )

          next if has_creator_role
          Codespaces::OrgPolicy.grant_billing_permission!(user, organization)
          GlobalInstrumenter.instrument("codespaces.org_enabled", { organization: organization })
          Codespaces::OrgSettingsChangedJob.perform_later(context: user.id, event_type: Codespaces::Events::ORG_CODESPACES_ENABLED_USER, actor_id: actor.id)

          emit_audit_log :codespaces_user_access_allowed, actor:, user:
          successful_users << user
        rescue Codespaces::OrgPolicy::RoleGranterError
          failed_users << user
        end
      end
      raise GrantFailedError.new("Failed to grant access for the following users: #{failed_users.map(&:login_for_api).join(', ')}") if failed_users.any?

      successful_users
    end

    sig { params(teams: ActiveRecord::AssociationRelation).returns(T::Array[::Team]) }
    def grant_access_for_teams(teams)
      successful_teams = []
      failed_teams = []

      teams.each do |team|
        begin
          has_creator_role = UserRole.find_by(
            actor: team,
            target_id: organization.id,
            target_type: "Organization",
            role: Role.codespace_org_creator_role.id
          )

          next if has_creator_role
          Codespaces::OrgPolicy.grant_billing_permission!(team, organization)
          GlobalInstrumenter.instrument("codespaces.org_enabled", { organization: organization })
          Codespaces::OrgSettingsChangedJob.perform_later(context: team.id, event_type: Codespaces::Events::ORG_CODESPACES_ENABLED_TEAM, actor_id: actor.id)

          emit_audit_log :codespaces_team_access_allowed, actor:, team:
          successful_teams << team
        rescue Codespaces::OrgPolicy::RoleGranterError
          failed_teams << team
        end
      end
      raise GrantFailedError.new("Failed to grant access for the following users: #{failed_teams.map(&:slug).join(', ')}") if failed_teams.any?

      successful_teams
    end

    sig { params(users: ActiveRecord::Relation).returns(T::Array[::User]) }
    def revoke_access_for_users(users)
      return [] if users.blank?

      result = Codespaces::OrganizationOptOut.call(organization: organization, actor: actor, users: users)
      result.removed_users.each { |user| emit_audit_log :codespaces_user_access_revoked, actor:, user: }
      if !result.success?
        raise RevokeFailedError.new("An error occurred when trying to revoke access, please try again later.")
      end
      result.removed_users
    end

    sig { params(teams: ActiveRecord::Relation).returns(T::Array[::Team]) }
    def revoke_access_for_teams(teams)
      return [] if teams.blank?

      result = Codespaces::OrganizationOptOut.call(organization: organization, actor: actor, teams: teams)
      result.removed_teams.each { |team| emit_audit_log :codespaces_team_access_revoked, actor:, team: }
      if !result.success?
        raise RevokeFailedError.new("An error occurred when trying to revoke access, please try again later.")
      end
      result.removed_teams
    end

    sig { params(event: Symbol, payload: T::Hash[String, String]).void }
    def emit_audit_log(event, payload = {})
      organization.instrument(event, payload)
    end
  end
end
