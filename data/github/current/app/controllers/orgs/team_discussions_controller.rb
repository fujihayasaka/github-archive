# typed: true
# frozen_string_literal: true

class Orgs::TeamDiscussionsController < Orgs::Controller
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    only: [:index, :show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  include Orgs::Invitations::RateLimiting
  include PjaxContentPolicy

  layout "layouts/team_two_column"
  javascript_bundle "manage-membership"

  before_action :login_required
  before_action :mask_analytics_data
  before_action :set_team_context_crumb, only: [:index, :show]

  def index
    redirect_to dashboard_path unless this_team
    redirect_to team_path(this_team)
  end

  def show
    redirect_to dashboard_path unless this_team
    redirect_to team_path(this_team)
  end

  private

  def selected_tab
    pinned_discussions_tab_selected? ? :pinned : :recent
  end

  def pinned_discussions_tab_selected?
    params[:pinned] == "1"
  end

  # Prepares client side data to report to google analytics
  def mask_analytics_data
    url = "/orgs/<org-login>/teams/<team-name>/discussions/#{action_name}"
    override_analytics_location url
  end
end
