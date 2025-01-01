# typed: true
# frozen_string_literal: true

class Codespaces::DevContainersController < AbstractRepositoryController

  before_action :require_codespaces_dev_container_landing_page_feature_flag

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:create],
    optional: true

  def create
    respond_to do |format|
      format.html do
        render "codespaces/dev_containers/create"
      end
    end
  end

  private

  def require_codespaces_dev_container_landing_page_feature_flag
    render_404 unless GitHub.flipper[:codespaces_dev_container_landing_page].enabled?(current_user)
  end

end
