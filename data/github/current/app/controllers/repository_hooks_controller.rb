# typed: true
# frozen_string_literal: true

class RepositoryHooksController < AbstractRepositoryController
  include HooksControllerMethods # All Hook related actions

  layout "repository"
  javascript_bundle :settings
  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    only: [:index]

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
    only: [:show]

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
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:index, :show, :new]

  private

  # Repo hooks
  def current_context
    current_repository
  end

  # Set up as a before_action in RepositoryControllerMethods.
  # Overloaded so that hooks aren’t visible to people who can pull public repos.
  def privacy_check
    has_permissions =
      if current_repository.owner.custom_roles_supported?
        current_repository.async_can_manage_webhooks?(current_user).sync
      else
        current_repository.adminable_by? current_user
      end

    return if has_permissions
    return render "admin/locked_repo" if logged_in? && current_user.site_admin?
    render_404
  end
end
