# typed: true
# frozen_string_literal: true

class Businesses::ExternalGroups::ExternalGroupTeamComponent < ApplicationComponent

  # How many mismatches will we load users for and render in the UI?
  # This is to prevent rendering a huge list of users in the UI and to prevent a huge query from being run.
  MISMATCH_LIST_CAP = 10

  attr_reader :team, :external_group_team, :business

  def initialize(team:, external_group_team:, business:)
    @team = team
    @external_group_team = external_group_team
    @business = business
    @mismatches = external_group_team_mismatches
  end

  def external_group_team_has_mismatches?
    # If the external_group_team is in sync, @mismatches will be set to nil
    # See ExternalGroupTeamComponent#external_group_team_mismatches
    return false unless @mismatches
    @mismatches[:group_member_ids_not_in_team].any? || @mismatches[:team_member_ids_not_in_group].any?
  end

  def transformed_external_group_team_mismatches_for_frontend
    group_members_not_in_team = User.where(id: @mismatches[:group_member_ids_not_in_team].slice(0, MISMATCH_LIST_CAP))
    team_members_not_in_group = User.where(id: @mismatches[:team_member_ids_not_in_group].slice(0, MISMATCH_LIST_CAP))

    {
      group_members_not_in_team: group_members_not_in_team.map { |u| transform_user_payload_for_react(u) },
      team_members_not_in_group: team_members_not_in_group.map { |u| transform_user_payload_for_react(u) },
      group_members_not_in_team_count: @mismatches[:group_member_ids_not_in_team].count,
      team_members_not_in_group_count: @mismatches[:team_member_ids_not_in_group].count,
    }
  end

  private

  def external_group_team_mismatches
    return nil if external_group_team.in_sync?
    external_group_team.calculate_group_team_mismatches
  end

  def transform_user_payload_for_react(user)
    {
      id: user.id,
      login: user.display_login,
      sso_url: enterprise_person_sso_enterprise_url(business, user),
      avatar_url: user.primary_avatar_url(40),
    }
  end
end
