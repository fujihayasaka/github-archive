# typed: true
# frozen_string_literal: true

class Orgs::Settings::BlockedUsers::SuggestionsController < Orgs::Controller
  before_action :login_required
  before_action :ensure_can_manage_blocked_users
  before_action :ensure_user_abuse_mitigation_enabled

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
    only: [:index],
    optional: true

  SUGGESTIONS_LIMIT = 10

  def index
    headers["Cache-Control"] = "no-cache, no-store"

    suggestions = User.search(params[:q], limit: SUGGESTIONS_LIMIT)

    render partial: "settings/blocked_users/suggestions/index", formats: :html, locals: {
      suggestions: suggestions,
    }
  end

  private

  def ensure_user_abuse_mitigation_enabled
    return render_404 unless GitHub.user_abuse_mitigation_enabled?
  end

  def ensure_can_manage_blocked_users
    render_404 unless this_organization.blocked_users_manageable_by?(current_user)
  end
end
