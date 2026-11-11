# typed: strict
# frozen_string_literal: true

class Settings::TeamsController < ApplicationController
  include Settings::ControllerMethods

  before_action :login_required

  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  sig { void }
  def index
    unless FeatureFlag.vexi.enabled?(:global_nav_react_teams_settings_page, current_user, default: false) && current_user.teams.any?
      return render_404
    end

    render "settings/teams/index", locals: {
      teams: current_user.teams,
      teams_payload: teams_payload,
    }
  end

  private

  sig { void }
  def teams_payload
    current_user.teams.map do |team|
      {
        id: team.id,
        name: team.combined_slug,
        url: team_path(team),
        avatar_url: team.primary_avatar_url(40),
      }
    end
  end
end
