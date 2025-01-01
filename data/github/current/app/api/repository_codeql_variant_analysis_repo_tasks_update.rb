# typed: true
# frozen_string_literal: true

class Api::RepositoryCodeqlVariantAnalysisRepoTasksUpdate < Api::App
  include VariantAnalysis::RepositoryResolutionHelper

  before do
    deliver_error! 404 if GitHub.enterprise?
  end

  rate_limit_as Api::RateLimitConfiguration::CODE_SCANNING_VARIANT_ANALYSIS_UPDATE_FAMILY

  def attempt_login
    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo }
    variant_analysis = CodeqlVariantAnalysis.load_variant_analysis_from_path_param(env, env["PATH_INFO"])
    if repo && variant_analysis
      scope = VariantAnalysis::SignedAuthToken.update_scope(repo.id, variant_analysis.id)
      login_from_remote_token(scope)
    end

    deliver_error!(403, message: "Must be logged in using a signed auth token") unless @remote_token_auth
  end

  patch "/repositories/:repository_id/code-scanning/codeql/variant-analyses/:codeql_variant_analysis_id/repositories/:variant_analysis_repo_id/status", operation_id: "code-scanning/update-variant-analysis-repo-task-status" do
    @route_owner = "@github/code-scanning-secexp"

    controller_repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    @accepted_scopes = controller_repo.public? ? %w(public_repo repo) : %w(repo)

    control_access :write_multi_repository_variant_analysis,
      resource: controller_repo,
      forbid: controller_repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    repo_task = get_repo_task(controller_repo, params)

    validate_non_final_status repo_task

    data = receive_with_openapi

    case data["status"]
    when "pending"
      # Only the background job should be able to set the status to pending
      deliver_error! 400, message: "Cannot set status to pending"

    when "succeeded"
      validate_succesful_status_for_repo_task data

      artifact_being_uploaded = repo_task.artifact_state == "starter" && repo_task.artifact_size > 0
      new_artifact_state = artifact_being_uploaded ? :uploaded : nil
      new_artifact_size = artifact_being_uploaded ? repo_task.artifact_size : nil

      repo_task.update(
        status: data["status"],
        result_count: data["result_count"],
        database_commit_sha: data["database_commit_sha"],
        source_location_prefix: data["source_location_prefix"],
        artifact_state: new_artifact_state,
        artifact_size: new_artifact_size)

    when "failed"
      validate_failure_status_for_repo_task data

      repo_task.update(
        status: data["status"],
        failure_message: data["failure_message"])

    when "in_progress", "canceled", "timed_out"
      repo_task.update(status: data["status"])

    else
      deliver_error! 400, message: "Invalid status"
    end

    deliver_empty status: 204
  end

  patch "/repositories/:repository_id/code-scanning/codeql/variant-analyses/:codeql_variant_analysis_id/repositories", operation_id: "code-scanning/update-variant-analysis-repo-tasks" do
    @route_owner = "@github/code-scanning-secexp"

    controller_repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    @accepted_scopes = controller_repo.public? ? %w(public_repo repo) : %w(repo)

    control_access :write_multi_repository_variant_analysis,
      resource: controller_repo,
      forbid: controller_repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    variant_analysis = CodeqlVariantAnalysis.find_by(
      id: params[:codeql_variant_analysis_id].to_i,
      controller_repo_id: controller_repo.id)
    deliver_error!(404, message: "Variant analysis not found") unless variant_analysis

    data = receive_with_openapi

    repository_ids = find_accessible_repositories(data["repository_ids"].map(&:to_i), current_user, cap_filter, skip_saml_authorization: @remote_token_auth.present?).pluck(:id)

    repo_tasks = CodeqlVariantAnalysisRepoTask.where(
      codeql_variant_analysis_id: variant_analysis.id,
      repository_id: repository_ids,
    ).where.not(status: CodeqlVariantAnalysisRepoTask::FINAL_STATUSES)

    case data["status"]
    when "pending", "in_progress", "succeeded"
      # These statuses should only be set from the background job or in the endpoint for a single repo task
      deliver_error! 400, message: "Cannot set status to #{data["status"]}"

    when "failed"
      validate_failure_status_for_repo_task data

      repo_tasks.each_slice(100) do |repo_tasks_slice|
        CodeqlVariantAnalysisRepoTask.transaction do
          repo_tasks_slice.each do |repo_task|
            repo_task.update(
              status: data["status"],
              failure_message: data["failure_message"]
            )
          end
        end
      end

    when "canceled", "timed_out"
      repo_tasks.each_slice(100) do |repo_tasks_slice|
        CodeqlVariantAnalysisRepoTask.transaction do
          repo_tasks_slice.each do |repo_task|
            repo_task.update(
              status: data["status"]
            )
          end
        end
      end

    else
      deliver_error! 400, message: "Invalid status"
    end

    deliver_empty status: 204
  end

  put "/repositories/:repository_id/code-scanning/codeql/variant-analyses/:codeql_variant_analysis_id/repositories/:variant_analysis_repo_id/artifact", operation_id: :internal do
    @route_owner = "@github/code-scanning-secexp"

    controller_repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    @accepted_scopes = controller_repo.public? ? %w(public_repo repo) : %w(repo)

    control_access :write_multi_repository_variant_analysis,
      resource: controller_repo,
      forbid: controller_repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    repo_task = get_repo_task(controller_repo, params)

    if CodeqlVariantAnalysisRepoTask::FINAL_STATUSES.include? repo_task.status
      deliver_error!(409, message: "Cannot upload artifact for a repository task that has already finished")
    end

    data = attr(receive(Hash), "size", "content_type", "name")
    params.each do |key, value|
      data[key.to_s] = value
    end

    # This is the equivalent of creator.create(current_user, data), but uses update instead
    # of create. This is because the repo task is already created, and we just need to
    # update it with the new data.
    repo_task.update(
      artifact_size: data[:size],
      artifact_content_type: data[:content_type],
      artifact_name: data[:name],
      uploader: current_user,
      artifact_state: :starter
    )

    if repo_task.valid?
      policy = repo_task.storage_policy(actor: current_user)
      GitHub.dogstats.increment("code_scanning.codeql_variant_analysis_repo_task.policy_created")
      deliver :policy_hash, policy, status: 201
    else
      deliver_error 422, errors: repo_task.errors
    end
  end

  private

  def get_repo_task(controller_repo, params)
    variant_analysis = CodeqlVariantAnalysis.find_by(
      id: params[:codeql_variant_analysis_id].to_i,
      controller_repo_id: controller_repo.id)
    deliver_error!(404, message: "Variant analysis not found") unless variant_analysis

    repo_task = CodeqlVariantAnalysisRepoTask.find_by(
      codeql_variant_analysis_id: variant_analysis.id,
      repository_id: params[:variant_analysis_repo_id].to_i)

    if repo_task.nil? || !repository_id_accessible?(repo_task.repository_id, current_user, cap_filter, skip_saml_authorization: @remote_token_auth.present?)
      deliver_error!(404, message: "Repository not found for variant analysis")
    end

    repo_task
  end

  def validate_non_final_status(repo_task)
    if CodeqlVariantAnalysisRepoTask::FINAL_STATUSES.include? repo_task.status
      deliver_error! 409, message: "Cannot update status for a repository task that has already finished"
    end
  end

  def validate_succesful_status_for_repo_task(data)
    if !data["result_count"] || !data["database_commit_sha"] || !data["source_location_prefix"]
      deliver_error! 400, message: "Missing 'result_count', 'database_commit_sha' or 'source_location_prefix'"
    end
  end

  def validate_failure_status_for_repo_task(data)
    if !data["failure_message"]
      deliver_error! 400, message: "Missing 'failure_message'"
    end
  end
end
