# typed: true
# frozen_string_literal: true

class Repos::DependabotAlertRefreshController < AbstractRepositoryController
  include ActionView::Helpers::DateHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Notify,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam

  before_action :can_manage_security_products?
  before_action :dependabot_alerts_enabled?

  def index
    manager = DependencyGraph::DataRefreshManager.new(current_repository)

    if manager.on_cooldown?
      flash[:error] = "Refresh not queued, you must wait to refresh again. Please try again later."
    else
      flash[:message] = "Refresh queued, it may take several minutes to see changes reflected in your alerts."
      manager.request_refresh!(actor: current_user)
    end

    redirect_to repository_alerts_path(
      user_id: current_repository.owner.display_login,
      repository: current_repository.name
    )
  end

  private

  def can_manage_security_products?
    render_404 unless SecurityProduct::Permissions::RepoAuthz.new(current_repository, actor: current_user).can_manage_repo_security_products?
  end

  def dependabot_alerts_enabled?
    render_404 unless current_repository.vulnerability_alerts_enabled?
  end
end
