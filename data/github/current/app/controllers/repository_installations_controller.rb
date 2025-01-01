# typed: true
# frozen_string_literal: true

class RepositoryInstallationsController < AbstractRepositoryController
  include IntegrationInstallationsControllerMethods

  PAGE_SIZE = 10

  layout "repository"
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Permissions,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:index]

  def index
    unless current_user.feature_flag_enabled_or_raise?(:fast_repository_installations) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      return super
    end

    installations =
      IntegrationInstallation.
        with_repository(current_repository).
        user_installable.
        joins(:integration).
        order("integrations.name asc").
        paginate(page: current_page, per_page: PAGE_SIZE)

    GitHub::PrefillAssociations.prefill_associations(installations, [
      :integration_install_trigger, { integration: [:owner] }
    ])

    render "repository_installations/index", locals: { installations: installations }
  end

  private

  def current_context
    current_repository
  end

  def target_for_conditional_access
    current_repository.owner
  end

  # Set up as a before_action in RepositoryControllerMethods.
  # Overloaded so installations aren’t visible to people who can pull public repos.
  def privacy_check
    return true if current_repository.adminable_by? current_user

    if logged_in? && current_user.site_admin?
      render "admin/locked_repo"
    else
      render_404
    end
  end
end
