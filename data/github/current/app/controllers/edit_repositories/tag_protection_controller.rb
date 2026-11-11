# typed: true
# frozen_string_literal: true

class EditRepositories::TagProtectionController < AbstractRepositoryController
  include TextHelper

  # Still need to check permissions even though we're only rendering a redirect. That's to keep people from probing
  # for the names of repos they don't have access to.
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
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    # We render the index page for now, because the page has a "tag protections were deprecated, use rules instead!" message
    render "edit_repositories/pages/tag_protection/index"
  end

  private

  def ensure_user_can_edit_repo_protections
    render_access_denied unless current_repository.async_can_edit_repo_protections?(current_user).sync
  end
end
