# typed: true
# frozen_string_literal: true

class RepositoryPagesSettingsController < AbstractRepositoryController # rubocop:todo GitHub/ControllersShouldHaveTests
  before_action :login_required

  javascript_bundle :settings
  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    ApplicationRecord::Pages,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:index]

  def index
    # Check if current user is an admin
    is_admin = current_repository.adminable_by?(current_user)
    # Or just a maintainer
    is_maintainer = !is_admin && can_manage_pages?

    # Both admin and maintainer are using the same view (the maintainer has a degraded experience)
    if is_admin || is_maintainer
      render "edit_repositories/pages/pages", locals: { is_maintainer: is_maintainer }
    else
      render_access_denied
    end
  end

  private

  # Is the user an FGP maintainer for some of this repository's Pages settings?
  def can_manage_pages?
    GitHub.pages_enabled? && current_repository.async_can_toggle_page_settings?(current_user).sync
  end

end
