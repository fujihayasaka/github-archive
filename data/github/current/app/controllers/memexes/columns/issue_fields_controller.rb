# typed: true
# frozen_string_literal: true

# The Memexes::Columns::IssueFieldsController controller handles importing issue fields into a project.
#
# It allows users with write access to a project to add an IssueField to their MemexProject stored as a MemexProjectColumn.
# The IssueFields must belong to the MemexProject owner. If there is a problem with importing the issue fields or
# if there are existing columns with the same name, it will return an error response to the user.
class Memexes::Columns::IssueFieldsController < Memexes::Controller
  include ApplicationController::VerifiedFetchDependency

  # Maximum number of issue fields that can be added to a MemexProject in a single request.
  MAX_ISSUE_FIELDS = 15

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Memexes::Columns::IssueFieldsController#create",
  ]

  before_action :login_required
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :user_has_write_access
  before_action :require_issue_fields_in_projects_enabled
  before_action :require_issue_fields_present
  before_action :enforce_issue_field_limit
  before_action :require_verified_email
  before_action :set_client_uid

  allow_verified_fetch

  # global critical dependencies, needed for all actions
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab

  # Required for loading the MemexProject and its columns
  depends_on_clusters ApplicationRecord::Memex

  # Required for loading IssueFields
  depends_on_clusters ApplicationRecord::IssuesPullRequests

  # Required for determining outside collaborator access to issue fields feature
  depends_on_clusters ApplicationRecord::Repositories

  def create
    columns = this_memex.add_issue_field_columns(issue_fields:, creator: current_user)

    if columns.all?(&:persisted?)
      render_columns(columns:, status: :created)
    else
      # Return a hash of errors indexed by issue_field_id
      errors = columns.select(&:invalid?).collect do |column|
        {
          issueFieldId: column.issue_field_id,
          errors: column.errors.full_messages,
        }
      end

      render json: { errors: }, status: :unprocessable_entity
    end
  end

  private

  memoize def issue_fields
    @issue_fields ||= if (ids = underscored_params[:issue_field_ids]) && (owner = this_memex&.owner)
      Issues.domain.issue_fields.issue_fields_for_org(owner:, ids:)
    else
      []
    end
  end

  def require_issue_fields_present
    return if issue_fields.any?

    render_base_error "Please select at least one issue field to import"
  end

  def enforce_issue_field_limit
    return if issue_fields.count <= MAX_ISSUE_FIELDS

    render_base_error "Cannot add more than #{MAX_ISSUE_FIELDS} issue fields in a single request"
  end

  def require_issue_fields_in_projects_enabled
    return unless (memex_project = this_memex)
    return if IssueFieldsFeature.enabled?(memex_project, actor: current_user)

    render_404
  end

  def render_base_error(message)
    render json: { errors: [message] }, status: :unprocessable_entity
  end
end
