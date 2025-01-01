# typed: true
# frozen_string_literal: true

class EditRepositories::TagProtectionController < AbstractRepositoryController
  include TextHelper

  before_action :ensure_user_can_edit_repo_protections, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Memex,
    only: [:new, :index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new, :index], optional: true

  def index
    # We render the index page for now, because the page has a "tag protections were deprecated, use rules!" message
    render "edit_repositories/pages/tag_protection/index"
  end

  def new
    render_404
  end

  def check_pattern # rubocop:todo GitHub/UseRestfulActions
    render_404
  end

  def create
    render_404
  end

  def delete # rubocop:todo GitHub/UseRestfulActions
    render_404
  end

  def import # rubocop:todo GitHub/UseRestfulActions
    render_404
  end

  private

  def ensure_user_can_edit_repo_protections
    render_access_denied unless current_repository.async_can_edit_repo_protections?(current_user).sync
  end
end
