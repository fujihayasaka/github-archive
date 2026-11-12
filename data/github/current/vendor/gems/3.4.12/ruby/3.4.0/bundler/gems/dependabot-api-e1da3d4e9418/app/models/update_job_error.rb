# frozen_string_literal: true

class UpdateJobError < ApplicationRecord
  # TODO: deprecate error types (migrate db column values):
  # - no_potential_pull_request
  # - unknown_no_potential_pull_request
  # No longer used but kept for UpdateJobIssue validity
  UPDATE_JOB_ERROR_TYPES = %w(
    all_versions_ignored
    bad_gitmodules
    branch_not_found
    cancelled_update
    dependency_file_content_not_changed
    dependency_file_not_evaluatable
    dependency_file_not_parseable
    dependency_file_not_resolvable
    dependency_file_not_supported
    dependency_not_found
    directory_not_found
    edited_pull_request_exists
    git_dependency_reference_not_found
    git_token_auth_error
    go_module_path_mismatch
    internal_pull_request_creation_failure
    job_repo_not_found
    misconfigured_tooling
    no_potential_pull_request
    octokit_rate_limited
    open_pull_request_limit_exceeded
    out_of_disk
    path_dependencies_not_reachable
    pull_request_creation_failure
    pull_request_creation_halted
    pull_request_exists_for_latest_version
    pull_request_exists_for_security_update
    registry_error
    resource_unavailable_to_installation
    secret_not_found
    secret_not_valid
    security_update_dependency_not_found
    security_update_not_found
    security_update_not_needed
    security_update_not_possible
    timed_out
    tool_feature_not_supported
    tool_version_not_supported
    transitive_update_not_possible
    unexpected_external_code
    unknown_no_potential_pull_request
    unresolvable_version
    update_not_possible
  ).freeze

  # We don't show errors for these because they need to be resolved by
  # the Dependabot team (or automatically by the app), not the user
  INTERNAL_UPDATE_JOB_ERRORS = %w(
    dependency_file_not_found
    file_fetcher_error
    octokit_unauthorized
    out_of_memory
    runner_error
    unknown_error
    update_files_error
    update_graph_error
  ).freeze

  # We don't create issues for these because they can't yet be resolved by
  # the user
  SILENCED_UPDATE_JOB_ERRORS = %w(
    git_dependencies_not_reachable
    missing_environment_variable
    private_source_authentication_failure
    private_source_bad_response
    private_source_certificate_failure
    private_source_not_reachable
    private_source_timed_out
  ).freeze

  # TODO: Recategorize ACTION_* errors in UpdateJob#error_category
  #
  # These are currently all treated as unexpected errors for SLO
  # purposes. We should revise this once our observability strategy
  # is clearer for Actions runners.
  #
  # These errors are raised when failing to request a dynamic workflow
  # from the Actions service
  ACTIONS_SERVICE_ERRORS = %w(
    actions_service_failed
    actions_service_repository_not_found
    actions_service_unavailable
    actions_service_unknown
    actions_service_unprocessable
  ).freeze
  # These errors are raised by the workflow itself when it encounters
  # a fatal error
  ACTIONS_WORKFLOW_ERRORS = %w(
    actions_workflow_image
    actions_workflow_unknown
    actions_workflow_updater
    self_hosted_runner_unavailable
  ).freeze

  UNPERSISTED_UPDATE_JOB_ERRORS = [
    *INTERNAL_UPDATE_JOB_ERRORS,
    *SILENCED_UPDATE_JOB_ERRORS,
  ].freeze

  ALLOWED_UPDATE_JOB_ERROR_TYPES = [
    *ACTIONS_SERVICE_ERRORS,
    *ACTIONS_WORKFLOW_ERRORS,
    *UPDATE_JOB_ERROR_TYPES,
    *UNPERSISTED_UPDATE_JOB_ERRORS,
  ].freeze

  belongs_to :update_job
  has_one :update_config, through: :update_job
  has_one :repo, through: :update_config

  validates :error_type, presence: true
  validates :update_job, presence: true

  serialize :error_details, coder: JSON

  after_create :instrument

  def error_presenter
    UpdateJobErrorPresenter.new(
      error_hash: error_hash,
      update_job: update_job,
    )
  end

  def error_hash
    {
      "error-type" => error_type,
      "error-detail" => error_details,
    }
  end

  private

  def instrument
    tags = {
      error_type: error_type,
      error_category: update_job.error_category(error_type: error_type),
    }
    if error_type == "git_dependencies_not_reachable"
      tags[:repository_access] = update_job.update_config.account.repository_accesses.any?
    end

    update_job.increment_metric(
      "job.error.created",
      tags: tags,
    )
  end
end
