# typed: true
# frozen_string_literal: true

class Memexes::MigrationController < Memexes::Controller
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :require_verified_email

  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :user_has_write_access

  before_action :require_project_not_deleted
  before_action :require_migration_for_project

  allow_verified_fetch only: [:create]

  rescue_from ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid, ActiveModel::ValidationError do |boom|
    T.bind(self, Memexes::MigrationController)
    Failbot.report_user_error(boom)
    render_json_error(
      error: "Operation could not be performed",
      status: :unprocessable_entity,
    )
  end

  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Memexes::MigrationController#create",
  ].freeze

  # global critical dependencies, needed for all actions
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Memex

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast,
    only: [:show],
    optional: true

  def show
    existing_migration = this_memex.project_migration
    source_project_id = existing_migration.source_project_id
    project = Project.find_by(id: source_project_id)

    return render_404 unless project

    render(json: {
      **existing_migration.as_json(root: false, methods: :is_automated, only: ProjectMigration::PROJECT_MIGRATION_FIELDS),
      source_project: {
        path: project.path,
        closed: project.closed?,
        name: project.name,
        empty: project.empty?
      }
    })
  end

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    only: [:create]

  def create
    migration = this_memex.project_migration

    unless migration.status == "completed"
      error = "Unable to acknowledge migration completion until actually completed"
      return render_json_error(error: error, status: :unprocessable_entity)
    end

    migration.update!(status: "completion_acknowledged")

    project = Project.find_by(id: migration.source_project_id)
    return render_404 unless project

    head :no_content
  end

  private

  def require_project_not_deleted
    return unless this_memex.deleted?

    render_404
  end

  def require_migration_for_project
    return if this_memex.project_migration

    render_404
  end
end
