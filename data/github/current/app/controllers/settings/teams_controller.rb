# typed: strict
# frozen_string_literal: true

class Settings::TeamsController < ApplicationController
  include Settings::ControllerMethods

  PER_PAGE = 30

  before_action :login_required
  skip_before_action :cap_pagination

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
    unless current_user.team_ids.any?
      return render_404
    end

    teams = Team.where(id: current_user.team_ids)
      .joins(:organization)
      .merge(Organization.active)
      .order(:id)
      .paginate(page: current_page, per_page: PER_PAGE)

    payload = {
      teams: teams_payload(teams),
      currentPage: current_page,
      perPage: PER_PAGE,
      totalCount: teams.total_entries,
    }

    if request.xhr?
      render(json: payload, status: :ok)
    else
      render "settings/teams/index", locals: { payload: payload }
    end
  end

  private

  sig { params(teams: T::Enumerable[Team]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def teams_payload(teams)
    teams.map do |team|
      {
        id: team.id,
        name: team.combined_slug,
        url: team_path(team),
        avatar_url: team.primary_avatar_url(40),
      }
    end
  end
end
