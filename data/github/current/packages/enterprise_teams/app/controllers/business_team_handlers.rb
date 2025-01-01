# typed: strict
# frozen_string_literal: true

module BusinessTeamHandlers
  sig { void }
  def business_teams_index; end

  sig { void }
  def business_teams_new; end

  sig { void }
  def business_teams_edit; end

  sig { void }
  def business_teams_create; end

  sig { void }
  def business_teams_update; end

  sig { void }
  def business_teams_destroy; end

  sig { void }
  def business_team_members_index; end

  sig { void }
  def business_team_members_create; end

  sig { void }
  def business_team_members_destroy; end
end
