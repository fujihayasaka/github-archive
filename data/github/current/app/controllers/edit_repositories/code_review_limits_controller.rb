# typed: true
# frozen_string_literal: true

class EditRepositories::CodeReviewLimitsController < AbstractRepositoryController
  before_action :require_feature
  before_action :ensure_admin_access

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
    ApplicationRecord::Memex,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    render "edit_repositories/code_review_limits/show"
  end

  def update
    if params[:restrict].present?
      current_repository.restrict_non_comment_pull_request_reviews(actor: current_user)
    else
      current_repository.unrestrict_non_comment_pull_request_reviews(actor: current_user)
    end

    flash[:notice] = "Code review limit settings saved."
    redirect_to repository_code_review_limits_path(current_repository.owner_display_login, current_repository.name)
  end

  private

  def require_feature
    render_404 unless GitHub.code_review_limits_enabled?
  end
end
