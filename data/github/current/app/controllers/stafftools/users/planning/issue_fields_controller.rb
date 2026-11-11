# typed: true
# frozen_string_literal: true

class Stafftools::Users::Planning::IssueFieldsController < StafftoolsController
  before_action :ensure_user_exists
  before_action :ensure_resync_issue_fields_enabled, only: :resync_issue_fields

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  layout "stafftools"

  def index
    render "stafftools/issue_fields/index",
      locals: {
        owner: this_user,
        issue_field_ids: ::Issues.domain.issue_fields.by_organization(this_user).map(&:id),
        issue_fields_in_projects: issue_field_ids_in_projects
      }
  end

  def resync_issue_fields # rubocop:todo GitHub/UseRestfulActions
    SyncIssueFieldToProjectColumnsJob.sync_later(issue_field_ids_in_projects)

    flash[:notice] = "Re-sync of all issue fields for this org in progress"
    redirect_back(fallback_location: stafftools_user_planning_issue_fields_path(this_user))
  end

  private

  def issue_field_ids_in_projects
    # Return all issue_field_ids that are present in any project columns for this org
    MemexProjectColumn
      .joins(:memex_project)
      .where(memex_projects: { owner_id: this_user.id })
      .where.not(issue_field_id: 0)
      .distinct
      .pluck(:issue_field_id)
  end

  def ensure_resync_issue_fields_enabled
    return unless FeatureFlag.vexi.enabled?(:enqueue_issue_fields_project_columns_sync_job_disabled, default: false)

    flash[:notice] = "Issue Field resync is currently disabled."
    redirect_back(fallback_location: stafftools_user_planning_issue_fields_path(this_user))
  end
end
