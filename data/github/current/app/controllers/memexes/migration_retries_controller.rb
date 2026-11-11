# typed: true
# frozen_string_literal: true

class Memexes::MigrationRetriesController < Memexes::Controller
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :require_verified_email

  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :user_has_write_access

  before_action :require_project_not_deleted
  before_action :require_migration_for_project
  before_action :require_cancel_permissions, only: :destroy

  allow_verified_fetch only: [:create, :destroy]

  rescue_from ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid, ActiveModel::ValidationError do |boom|
    T.bind(self, Memexes::MigrationRetriesController)
    Failbot.report_user_error(boom)
    render_json_error(error: "Operation could not be performed", status: :unprocessable_entity)
  end

  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Memexes::MigrationRetriesController#create",
    "Memexes::MigrationRetriesController#destroy",
  ].freeze

  # global critical dependencies, needed for all actions
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Memex

  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    only: [:create]

  depends_on_clusters ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::Repositories,
    only: [:create],
    optional: true

  def create
    existing_migration = this_memex.project_migration
    project = Project.find_by(id: existing_migration.source_project_id)
    return render_404 unless project

    project_migration = MemexProject::Migrator.initialize!(current_user, project)
    project_migration.save

    MigrateLegacyProjectJob.perform_later(project_migration.id)
    memex_project = project_migration.memex_project
    project_owner = memex_project.owner

    show_memex_path = if project_owner.is_a?(Organization)
      show_org_memex_path(project_owner, memex_project.number)
    else
      show_user_memex_path(project_owner, memex_project.number)
    end

    project.notify_metadata_subscribers

    existing_migration.destroy
    this_memex.destroy

    render(json: { redirectUrl: show_memex_path })
  end

  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    only: [:destroy],
    optional: true

  def destroy
    project = Project.find_by(id: this_memex.project_migration.source_project_id)
    return render_404 unless project

    this_memex.project_migration.destroy
    this_memex.destroy

    render(json: { redirectUrl: project_path(project) })
  end

  private

  def require_project_not_deleted
    render_404 if this_memex.deleted?
  end

  def require_migration_for_project
    render_404 unless this_memex.project_migration
  end

  def require_cancel_permissions
    return if this_memex.project_migration.requester == current_user && !project_migration_completed?
    render_404
  end

  def project_migration_completed?
    %w[completed completion_acknowledged].include?(this_memex.project_migration.status)
  end
end
