# typed: true
# frozen_string_literal: true

class Stafftools::DependabotController < StafftoolsController

  before_action :ensure_user_exists
  before_action :ensure_dependabot_available

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Billing,
    ApplicationRecord::Pages,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    repo_access_visible = this_user.organization?

    if repo_access_visible
      begin
        repo_access = Dependabot::Twirp.repository_access_service_client.get_repository_access(owner_github_id: this_user.id)
        repos_view = Stafftools::Dependabot::AccessReposView.new(
          user: current_user, page: params[:repo_page], repo_ids: repo_access.repository_github_ids)
      rescue Dependabot::Twirp::BaseError, Faraday::ConnectionFailed
        repo_access_service_unavailable = true
      end
    end

    render "stafftools/dependabot/show",
      layout: "layouts/stafftools/organization/content",
      locals: {
        owner: this_user,
        repo_access: repo_access,
        repo_access_visible: repo_access_visible,
        repo_access_service_unavailable: repo_access_service_unavailable,
        repos_view: repos_view
      }
  end

  private

  def ensure_dependabot_available
    render_404 unless GitHub.dependabot_enabled?
  end
end
