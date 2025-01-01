# typed: true
# frozen_string_literal: true

class Stafftools::Teams::MigrationOverrideComponent < ApplicationComponent
  attr_reader :team

  SPLUNK_URL = "https://splunk.githubapp.com/en-US/app/gh_reference_app/search"
  SPLUNK_PARAMS = "index=rails team_id=%{team_id}"

  def initialize(team:)
    @team = team
  end

  private

  def render?
    team.team_discussion_migration_can_be_resumed?
  end

  memoize def splunk_url
    query = {
      q: SPLUNK_PARAMS % {
        team_id: team.id
      }
    }
    "#{SPLUNK_URL}?#{query.to_query}"
  end

  def form_path
    migration_override_stafftools_user_team_path(team.organization.display_login, team.slug)
  end
end
