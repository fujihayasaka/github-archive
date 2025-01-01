# typed: true
# frozen_string_literal: true

class ProjectMigration < ApplicationRecord::Domain::Memexes
  belongs_to :project, foreign_key: :source_project_id, inverse_of: :project_migration
  belongs_to :memex_project, foreign_key: :target_memex_project_id, inverse_of: :project_migration
  belongs_to :requester, class_name: "User"

  validates :project, presence: true, on: :create
  validates :requester, presence: true, on: :create
  validates :memex_project, presence: true, on: :update

  enum :status, {
    pending: 0,
    in_progress_project_details: 1,
    in_progress_status_fields: 2,
    in_progress_default_view: 3,
    in_progress_permissions: 4,
    in_progress_items: 5,
    in_progress_workflows: 6,
    completed: 7,
    error: 8,
    completion_acknowledged: 9
  }

  PROJECT_MIGRATION_FIELDS = %i[
    id
    source_project_id
    target_memex_project_id
    status
    requester_id
    last_retried_at
    last_migrated_project_item_id
    completed_at
    updated_at
    created_at
    source_project
  ].freeze

  def has_completed?(step)
    current_status = ProjectMigration.statuses[status]
    current_status.nil? ? false : current_status > T.must(ProjectMigration.statuses[step])
  end

  alias_method :completed_not_acknowledged?, :completed?

  def completed?
    completed_not_acknowledged? || completion_acknowledged?
  end

  def reset!
    update!(
      status: :pending,
      last_migrated_project_item_id: nil,
    )
  end

  def is_automated
    # MemexAutomation.bot is only optional here as to not require setting up the integration bot in each test suite
    # which may interact with migrations
    requester_id == Apps::Internal::MemexAutomation.bot&.id
  end

  def status_payload
    if error?
      { status: "ERROR",  message: "Unable to migrate project" }
    elsif completed?
      { status: "COMPLETED",  message: "Migration complete!" }
    elsif in_progress_workflows?
      { status: "IN_PROGRESS_WORKFLOWS", message: "Migrating to Projects" }
    elsif in_progress_items?
      { status: "IN_PROGRESS_ITEMS", message: "Migrating to Projects" }
    elsif in_progress_permissions?
      { status: "IN_PROGRESS_PERMISSIONS", message: "Migrating to Projects" }
    elsif in_progress_default_view?
      { status: "IN_PROGRESS_DEFAULT_VIEW", message: "Migrating to Projects" }
    elsif in_progress_status_fields?
      { status: "IN_PROGRESS_STATUS_FIELDS", message: "Migrating to Projects" }
    elsif in_progress_project_details?
      { status: "IN_PROGRESS_PROJECT_DETAILS", message: "Migrating to Projects" }
    else
      { status: "PENDING", message: "Migrating to Projects" }
    end
  end
end
