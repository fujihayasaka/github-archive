# typed: true
# frozen_string_literal: true

require "set"

# CodeqlBulkBuilderBatchJob launches Action workflows that attempt
# to build CodeQL databases for repositories.
class CodeqlBulkBuilderBatchJob < ApplicationJob
  queue_as :code_scanning_multi_repository_variant_analysis

  retry_on_dirty_exit

  # repos_to_build - Array of [repo_id, language, last_attempted] pairs to build
  # ref            - Ref to use in the workflow.
  def perform(repos_to_build:, ref: "main")
    return if GitHub.enterprise?
    return if GitHub.flipper[:disable_codeql_database_builder_job].enabled?

    controller_repo = Repository.with_name_with_owner("codeql/bulk-builder")
    code_scanning_bot = Apps::Internal.integration(:code_scanning).bot

    # Filter out private or archived or non-existent repos
    all_repo_ids = repos_to_build.map { |id, _, _| id }.to_set
    valid_repos = Repository.where(id: all_repo_ids)
      .public_scope.not_archived_scope
      .pluck(:id, :owner_login, :name)
      .map { |id, owner_login, name| [id, "#{owner_login}/#{name}"] }
      .to_h
    private_or_archived_count = all_repo_ids.size - valid_repos.size
    repos_to_build, invisible_repos = repos_to_build.partition { |id, _, _| valid_repos.key?(id) }

    # Filter out repos where the latest DB was not uploaded by the bulk builder
    user_uploaded_dbs = CodeqlDatabase.latest_database_is_user_uploaded(
      repos_to_build.map { |id, language, _| [id, language] },
      code_scanning_bot.id
    )
    repos_to_build, uploaded_db = repos_to_build.partition { |id, language, _| !user_uploaded_dbs.include?([id, language]) }

    # Filter out repos where the repository has not been pushed to since the last bulk build
    updated_repos = Repository.where(id: all_repo_ids).pluck(:id, :pushed_at).to_h
    repos_to_build, not_pushed_repos = repos_to_build.partition do |repo_id, _, last_attempted|
      last_attempted = last_attempted || CodeqlBulkBuilderConfig::NEVER_HAPPENED
      pushed_at = updated_repos[repo_id] || CodeqlBulkBuilderConfig::NEVER_HAPPENED

      pushed_at > last_attempted
    end

    # Filter out repos that don't have the language they are onboarded for
    repos_to_build, language_unavailable = CodeqlBulkBuilderConfig.partition_repos_without_languages(repos_to_build)

    # Schedule builds for all remaining repos
    repos_to_build.each do |repo_id, language, _|
      nwo = valid_repos[repo_id]
      sat = code_scanning_bot.signed_auth_token({
        scope: Api::RepositoryCodeScanningDatabases::signed_auth_token_upload_scope(repo_id),
        expires: 1.day.from_now
      })

      controller_repo.dispatch_workflow_event(
        code_scanning_bot.id,
        ".github/workflows/codeql-build-database.yml",
        ref,
        {
          "enqueued_at" => Time.now.utc.iso8601,
          "repository_id" => repo_id,
          "nwo" => nwo,
          "sat" => sat,
          "language" => language,
          "mode" => "build",
        }
      )
    end

    GitHub.dogstats.count("code_scanning.remote_queries.autobuild", repos_to_build.size, tags: ["action:build"])
    GitHub.dogstats.count("code_scanning.remote_queries.autobuild", user_uploaded_dbs.size, tags: ["action:db_not_bulk_built"])
    GitHub.dogstats.count("code_scanning.remote_queries.autobuild", private_or_archived_count, tags: ["action:private_or_archived"])
    GitHub.dogstats.count("code_scanning.remote_queries.autobuild", not_pushed_repos.size, tags: ["action:repo_not_pushed"])
    GitHub.dogstats.count("code_scanning.remote_queries.autobuild", language_unavailable.size, tags: ["action:language_not_available"])

    # Return repos we can safely offboard from the bulk builder
    repos_to_offboard = invisible_repos + uploaded_db + language_unavailable

    with_write do
      # Offboard repos that are private, archived, non-existent or that have not been uploaded by the bulk builder
      repos_to_offboard.each_slice(100) do |batch|
        CodeqlBulkBuilderConfig.repos_and_languages(batch).delete_all
      end
    end
    GitHub.logger.info("codeql_bulk_builder_batch_job offboarding repos", { repos_and_languages: repos_to_offboard }) if repos_to_offboard.present?
  end
end
