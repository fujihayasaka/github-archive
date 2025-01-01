# typed: true
# frozen_string_literal: true

# CodeqlVariantAnalysisProcessingJob is responsible for processing a user's request for
# executing a multi-repo variant analysis. It is triggered manually when a request
# to create a variant analysis is successful.
#
# It is responsible for:
# - Validating the list of repositories
# - Creating and uploading an instructions file
# - Creating a dynamic Actions workflow
# - Updating various Variant Analysis tables
# - Raising hydro message to notify of new analysis
# - Onboarding any missing repositories to the bulk builder.
class CodeqlVariantAnalysisProcessingJob < ApplicationJob
  include VariantAnalysis::RepositoryResolutionHelper
  include VariantAnalysis::RepositoryValidationHelper
  include VariantAnalysis::StorageHelper
  include VariantAnalysis::ActionsWorkflowHelper

  queue_as :code_scanning_multi_repository_variant_analysis

  # If the worker shuts down the job then the job will be retried.
  retry_on_dirty_exit

  def perform(
    variant_analysis_id:,
    action_repo_ref:,
    repository_ids:
  )

    variant_analysis = CodeqlVariantAnalysis.find_by(id: variant_analysis_id)
    if !variant_analysis
      raise StandardError, "Invalid variant analysis id #{variant_analysis_id}"
    end

    repo_filter_result = filter_repos_to_skip_from_processing(variant_analysis, repository_ids)
    repo_ids = repo_filter_result[:repos_ids_to_process]

    if repo_ids.empty?
      update_variant_analysis_record(
        variant_analysis: variant_analysis,
        failure_reason: "no_repos_queried"
      )
      analyse_repos_for_onboarding(repo_filter_result[:no_codeql_db_repo_ids], variant_analysis)
      return
    end

    begin
      workflow_run_id = create_actions_workflow(variant_analysis, repo_ids, action_repo_ref)
    rescue VariantAnalysis::ActionsWorkflowHelper::InputsTooLarge,
           VariantAnalysis::ActionsWorkflowHelper::UnableToLaunch,
           VariantAnalysis::ActionsWorkflowHelper::InvalidActionRepoRef => e
      fail_variant_analysis_with_internal_error(variant_analysis, e)
      return
    end

    update_variant_analysis_record(
      variant_analysis: variant_analysis,
      workflow_run_id: workflow_run_id
    )
    create_variant_analysis_repo_task_records(
      variant_analysis: variant_analysis,
      repo_ids: repo_ids
    )
    create_hydro_event(variant_analysis, repo_ids.length)
    analyse_repos_for_onboarding(repo_filter_result[:no_codeql_db_repo_ids], variant_analysis)
  end

  private

  def filter_repos_to_skip_from_processing(variant_analysis, repository_ids)
    repos_ids_to_process = repository_ids
    repos_ids_to_process, not_found_repo_ids = partition_on_existing_repos(repos_ids_to_process)
    repos_ids_to_process, privacy_mismatch_repo_ids = partition_on_controller_repo_privacy(repos_ids_to_process, variant_analysis.controller_repo)
    repos_ids_to_process, no_codeql_db_repo_ids = partition_on_db_availability(repos_ids_to_process, variant_analysis.query_language)
    repos_ids_to_process, over_limit_repo_ids = partition_on_max_repos(repos_ids_to_process)

    ActiveRecord::Base.connected_to(role: :writing) do
      variant_analysis.update!(
        privacy_mismatch_repo_ids: privacy_mismatch_repo_ids.take(100).join(","),
        privacy_mismatch_repo_count: privacy_mismatch_repo_ids.count,
        no_codeql_db_repo_ids: no_codeql_db_repo_ids.take(100).join(","),
        no_codeql_db_repo_count: no_codeql_db_repo_ids.count,
        over_limit_repo_ids: over_limit_repo_ids.take(100).join(","),
        over_limit_repo_count: over_limit_repo_ids.count
      )
    end

    {
      repos_ids_to_process: repos_ids_to_process,
      privacy_mismatch_repo_ids: privacy_mismatch_repo_ids,
      no_codeql_db_repo_ids: no_codeql_db_repo_ids,
      over_limit_repo_ids: over_limit_repo_ids
    }
  end

  def fail_variant_analysis_with_internal_error(variant_analysis, error)
    update_variant_analysis_record(
      variant_analysis: variant_analysis,
      failure_reason: "internal_error")

    # Internal errors indicate a bug with our code or an issue when
    # trying to communicate with other components (e.g. Actions) so
    # we want to make sure they are logged.
    Failbot.report(error, "gh.code_scanning.variant_analysis.id": variant_analysis.id)
  end

  def update_variant_analysis_record(variant_analysis:, workflow_run_id: nil, failure_reason: nil)
    ActiveRecord::Base.connected_to(role: :writing) do
      variant_analysis.update!(
        actions_workflow_run_id: workflow_run_id,
        failure_reason: failure_reason
      )
    end
  end

  def create_variant_analysis_repo_task_records(variant_analysis:, repo_ids:)
    ActiveRecord::Base.connected_to(role: :writing) do
      repo_ids.each_slice(100) do |repo_ids_slice|
        CodeqlVariantAnalysisRepoTask.transaction do
          repo_ids_slice.each do |repo_id|
            CodeqlVariantAnalysisRepoTask.create!(
              codeql_variant_analysis_id: variant_analysis.id,
              repository_id: repo_id,
              status: "pending"
            )
          end
        end
      end
    end
  end

  def create_actions_workflow(variant_analysis, repo_ids, action_repo_ref)
    instructions_url = create_instructions_file(variant_analysis, repo_ids)

    create_workflow_run(
      variant_analysis: variant_analysis,
      instructions_url: instructions_url,
      action_repo_ref: action_repo_ref,
      repo_count: repo_ids.count)
  end

  def create_instructions_file(variant_analysis, repo_ids)
    repo_ids_with_nwos = resolve_repo_nwos_from_ids(repo_ids)

    repo_nwo_chunks = create_repo_nwo_chunks(variant_analysis, repo_ids_with_nwos.values)

    repo_ids_with_db_urls = []
    databases_by_repo = get_codeql_dbs(repo_ids, variant_analysis.query_language)

    repo_ids.each do |repo_id|
      database = databases_by_repo[repo_id]
      next if database.nil?

      storage_path = database.storage_s3_key(nil)
      download_url = create_signed_url(storage_path, CodeqlDatabase::STORAGE_DOWNLOAD_EXPIRATION)
      repo_ids_with_db_urls.push({
        id: repo_id,
        nwo: repo_ids_with_nwos[repo_id],
        downloadUrl: download_url
      })
    end

    instructions_file_content = {
      "repositories" => repo_ids_with_db_urls,
      "repoNwoChunks" => repo_nwo_chunks,
      # Forward the feature flags that determine the default version of CodeQL
      "features" => GitHub::CodeQLAction.default_version_flags(variant_analysis.controller_repo),
    }

    upload_instructions_file(variant_analysis, instructions_file_content.to_json)
  end

  def get_codeql_dbs(repo_ids, language)
    CodeqlDatabase.latest_for_repos_and_languages(repo_ids.map { |repo_id| [repo_id, language] })
      # We only looked up for a single language, so we can simplify the map keys
      .map { |k, v| [k[0], v] }.to_h
  end

  def analyse_repos_for_onboarding(no_codeql_db_repo_ids, variant_analysis)
    return if !GitHub.flipper[:remote_queries_queries_onboard_repos].enabled?(variant_analysis.actor)

    no_codeql_db_repo_ids.each_slice(500).flat_map do |ids|
      public_repo_ids = Repository.where(id: ids, public: true)
                            .pluck(:id)
                            .map { |repo_id| [repo_id, variant_analysis.query_language] }
      CodeqlBulkBuilderOnboardJob.perform_later(repos_and_languages: public_repo_ids)
    end
  end

  def create_hydro_event(variant_analysis, repo_count)
    # Create a hydro event for observability and metrics.
    GlobalInstrumenter.instrument("code_scanning.remote_query_run", {
      controller_repository: variant_analysis.controller_repo,
      actor: variant_analysis.actor,
      created_at: Time.now,
      language: variant_analysis.query_language,
      repositories_count: repo_count,
    })
  end
end
