# typed: true
# frozen_string_literal: true

module Api::Serializer::RepositoryCodeqlVariantAnalysisDependency
  extend T::Helpers
  requires_ancestor { Api::Serializer::RepositoriesDependency }

  include VariantAnalysis::StorageHelper

  def repository_codeql_variant_analysis_hash(data, options = {})
    options = Api::SerializerOptions.from(options)

    variant_analysis = data[:variant_analysis]
    repositories = data[:repositories]

    hash = {
      id: variant_analysis.id,
      controller_repo: simple_repository_hash(variant_analysis.controller_repo, content_options(options)),
      actor: simple_user_hash(variant_analysis.actor, content_options(options)),
      query_language: variant_analysis.query_language,
      query_pack_url: create_signed_url(variant_analysis.query_pack_path, 1.hour),
      created_at: time(variant_analysis.created_at),
      updated_at: time(variant_analysis.updated_at)
    }

    if variant_analysis.failure_reason
      hash[:status] = "failed"
      hash[:failure_reason] = variant_analysis.failure_reason
    elsif variant_analysis.actions_workflow_run_id
      hash[:actions_workflow_run_id] = variant_analysis.actions_workflow_run_id
      actions_workflow_run = Actions::WorkflowRun.find_by(id: variant_analysis.actions_workflow_run_id)

      if actions_workflow_run&.completed_at
        hash[:completed_at] = time(actions_workflow_run.completed_at)
      end

      if actions_workflow_run&.succeeded?
        hash[:status] = "succeeded"
      elsif actions_workflow_run&.cancelled?
        hash[:status] = "cancelled"
      elsif actions_workflow_run&.completed?
        # It's not cancelled or succeeded, but has completed, so it must have failed.
        hash[:status] = "failed"
        hash[:failure_reason] = "actions_workflow_run_failed"
      else
        hash[:status] = "in_progress"
      end
    elsif variant_analysis.created_at < 5.hours.ago
      hash[:status] = "failed"
      hash[:failure_reason] = "internal_error"
      hash[:completed_at] = time(variant_analysis.created_at + 5.hours)
    else
      hash[:status] = "in_progress"
    end

    if variant_analysis.codeql_variant_analysis_repo_tasks.any?
      hash[:scanned_repositories] = variant_analysis.codeql_variant_analysis_repo_tasks.filter_map do |repo_task|
        simple_repository_codeql_variant_analysis_repo_task_hash({ repo_task: repo_task, repositories: repositories }, content_options(options))
      end
    end

    if options.current_user&.id == variant_analysis.actor_id
      access_mismatch_repos = repository_codeql_variant_analysis_skipped_repo_group_hash({
        repo_count: variant_analysis.privacy_mismatch_repo_count,
        repo_ids: variant_analysis.privacy_mismatch_repo_ids,
        repositories: repositories
      }, content_options(options))

      no_codeql_db_repos = repository_codeql_variant_analysis_skipped_repo_group_hash({
        repo_count: variant_analysis.no_codeql_db_repo_count,
        repo_ids: variant_analysis.no_codeql_db_repo_ids,
        repositories: repositories
      }, content_options(options))

      over_limit_repos = repository_codeql_variant_analysis_skipped_repo_group_hash({
        repo_count: variant_analysis.over_limit_repo_count,
        repo_ids: variant_analysis.over_limit_repo_ids,
        repositories: repositories
      }, content_options(options))

      not_found_repos = {
        repository_count: variant_analysis.not_found_repo_count || 0,
        repository_full_names: variant_analysis.not_found_repo_nwos&.split(",") || []
      }

      hash[:skipped_repositories] = {
        access_mismatch_repos: access_mismatch_repos,
        not_found_repos: not_found_repos,
        no_codeql_db_repos: no_codeql_db_repos,
        over_limit_repos: over_limit_repos
      }
    end

    hash.compact
  end

  def simple_repository_codeql_variant_analysis_repo_task_hash(data, options = {})
    repo_task = data[:repo_task]

    repository = if data.key?(:repositories)
      data[:repositories][repo_task.repository_id]
    else
      repo_task.repository
    end

    return nil if repository.blank?

    hash = {
      repository: repository_codeql_variant_analysis_repo_hash(repository, options),
      analysis_status: repo_task.status,
      result_count: repo_task.result_count,
      failure_message: repo_task.failure_message
    }

    if repo_task.uploaded?
      hash[:artifact_size_in_bytes] = repo_task.artifact_size
    end

    hash.compact
  end

  def repository_codeql_variant_analysis_skipped_repo_group_hash(data, options = {})
    repository_count = data[:repo_count] || 0
    repository_ids = data[:repo_ids] || ""
    loaded_repositories = data[:repositories] || {}

    repository_ids = repository_ids.split(",").map(&:to_i)
    repositories = loaded_repositories
      .values_at(*repository_ids)
      .compact
      .map { |r| repository_codeql_variant_analysis_repo_hash(r, options) }

    {
      repository_count: repository_count,
      repositories: repositories
    }
  end

  def repository_codeql_variant_analysis_repo_task_hash(repo_task, options = {})
    options = Api::SerializerOptions.from(options)

    hash = simple_repository_codeql_variant_analysis_repo_task_hash({ repo_task: repo_task }, options).merge!(
      # Override the default behavior by including the full simple repository instead of just the identifiers
      repository: simple_repository_hash(repo_task.repository, content_options(options)),
      database_commit_sha: repo_task.database_commit_sha,
      source_location_prefix: repo_task.source_location_prefix
    )

    if repo_task.uploaded?
      hash[:artifact_url] = repo_task.url(actor: options.current_user)
    end

    hash.compact
  end

  def repository_codeql_variant_analysis_repo_hash(repo, options = {})
    return T.must(repository_identifier_hash(repo, options)).merge!(
      stargazers_count: repo.stargazer_count,
      updated_at: time(repo.updated_at)
    ) if repo.is_a?(Repository)

    {
      id: repo[:id],
      name: repo[:name],
      full_name: repo[:nwo],
      private: repo[:private],
      stargazers_count: repo[:stargazer_count],
      updated_at: time(repo[:updated_at])
    }
  end
end
