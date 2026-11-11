# typed: true
# frozen_string_literal: true

class Orgs::Settings::DiscussionsController < Orgs::Controller
  before_action :login_required
  before_action :organization_admin_required
  before_action :ensure_discussions_available

  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    only: [:show]

  DOCS_URL = "/organizations/managing-organization-settings/enabling-or-disabling-github-discussions-for-an-organization#about-organization-discussions"

  def show
    render "settings/organization/discussions/show"
  end

  def update
    success = if params[:discussions_enabled] == "1"
      org_discussion_repo.repository = repository
      org_discussion_repo.actor = current_user
      org_discussion_repo.save
    else
      org_discussion_repo.destroy
    end

    if success
      if org_discussion_repo.destroyed?
        flash[:notice] = "Organization discussions have been disabled."
      else
        flash[:success] = "Organization discussions has been set up!"
      end
    else
      flash[:error] = org_discussion_repo.errors.full_messages.join(", ")
    end

    redirect_to organization_settings_discussions_path(current_organization)
  end

  private

  def is_private_or_internal_repo?
    repository && (repository.private? || repository.internal?)
  end

  memoize def org_discussion_repo
    current_organization.discussion_repository || current_organization.build_discussion_repository
  end

  memoize def repository
    current_organization.repositories.find_by(id: params[:repo_id])
  end

  def ensure_discussions_available
    render_404 unless GitHub.discussions_available_on_platform?
  end
end
