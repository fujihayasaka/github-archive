# typed: true
# frozen_string_literal: true

class Orgs::Settings::Moderators::SuggestionsController < Orgs::Controller
  before_action :login_required
  before_action :organization_admin_required
  before_action :ensure_moderation_features_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  SUGGESTIONS_MAXIMUM = 10

  def index
    headers["Cache-Control"] = "no-cache, no-store"

    render partial: "orgs/settings/moderators/suggestions/index",
      formats: :html,
      locals: {
        suggestions: suggestions,
      }
  end

  private

  def suggestions # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @suggestions if defined?(@suggestions)

    existing_moderators = this_organization.moderators
    existing_user_ids = existing_moderators.select { |moderator| moderator.is_a?(User) }.map(&:id)
    existing_team_ids = existing_moderators.select { |moderator| moderator.is_a?(Team) }.map(&:id)
    search_query = params[:q].to_s

    candidate_teams = Team.search_name_and_slug(
      query: search_query,
      scope: this_organization.teams.where.not(id: existing_team_ids),
    ).limit(SUGGESTIONS_MAXIMUM)

    candidate_users = User.search(
      search_query,
      org: this_organization,
      org_member_scope: :all,
      limit: SUGGESTIONS_MAXIMUM,
    ).reject { |user| existing_user_ids.include?(user.id) }

    @suggestions = candidate_teams + candidate_users
  end

  def ensure_moderation_features_enabled
    render_404 unless GitHub.organization_moderators_enabled?
  end
end
