# typed: true
# frozen_string_literal: true

class Organizations::Settings::SecurityConfigurations::FilterSuggestionsController < Orgs::Controller
  extend T::Sig
  include EnablementSettingsDependency

  # Access
  before_action :manage_security_products_permission_required

  TYPE_AHEAD_RESULT_SIZE = 10

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Notify,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Ballast,
    only: [:teams]
  def teams # rubocop:todo GitHub/UseRestfulActions
    teams = fetch_teams.map do |team|
      {
        name: team.name,
        slug: team.combined_slug,
        avatar_url: team.primary_avatar_url(60),
      }
    end

    render json: { teams: teams }
  end

  private

  def fetch_teams
    return [] if params[:filter_value].nil?

    scope = current_organization.visible_teams_for(current_user)
      .where("teams.name LIKE ? OR teams.slug LIKE ?", "#{params[:filter_value]}%", "#{params[:filter_value]}%")

    T.unsafe(Team).ranked_for(current_user, scope: scope).limit(TYPE_AHEAD_RESULT_SIZE)
  end
end
