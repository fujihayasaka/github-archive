# typed: true
# frozen_string_literal: true

# CodeqlBulkBuilderOnboardJob onboards repositories to CodeQL database bulk building.
# See also: CodeqlBulkBuilderConfig and CodeqlBulkBuilderJob
class CodeqlBulkBuilderOnboardJob < ApplicationJob
  queue_as :code_scanning_multi_repository_variant_analysis

  retry_on_dirty_exit

  # repos_and_languages - Array of [repo_id, language] pairs to onboard
  def perform(repos_and_languages:)
    return if GitHub.enterprise?

    # Activate existing inactive repos
    with_write do
      repos_and_languages.each_slice(1000) do |slice|
        CodeqlBulkBuilderConfig.where(is_active: false).repos_and_languages(slice).update_all(is_active: true, consecutive_build_failures: 0)
      end
    end

    # Do an initial filter to kick out already onboarded repos
    repos_and_languages = CodeqlBulkBuilderConfig.not_onboarded(repos_and_languages)

    # Filter out any languages which are not supported by the bulk builder
    repos_and_languages.select! { |_, language| CodeqlBulkBuilderConfig::ALLOWED_LANGUAGES.include?(language) }

    # Look up all the repository objects, and filter to only public and non-archived repos.
    # Then remove any repos that don't exist or not match our criteria.
    ids = repos_and_languages.map(&:first)
    repos_by_id = Repository.public_scope.not_archived_scope.where(id: ids).select(:id).index_by(&:id)
    repos_and_languages.select! { |id, _| repos_by_id.key?(id) }

    # Filter out any repository/language pairs where the latest database
    # was not uploaded by the bulk builder.
    # We only want to onboard repos that haven't had a database uploaded by a user
    code_scanning_bot = Apps::Internal.integration(:code_scanning).bot
    repos_and_languages -= CodeqlDatabase.latest_database_is_user_uploaded(repos_and_languages, code_scanning_bot.id)

    # Filter out repositories that don't have the language they should be onboarded with
    repos_and_languages, language_unavailable = CodeqlBulkBuilderConfig.partition_repos_without_languages(repos_and_languages)
    GitHub.logger.info("codeql_bulk_builder_batch_job not onboarded repos because language not available", { repos_and_languages: language_unavailable })

    # Onboard each repo/language separately.
    # Doing this in bulk upserts is unfortunately potentially dangerous.
    CodeqlBulkBuilderConfig.throttle_writes do
      repos_and_languages.each do |repo_id, language|
        repos_by_id[repo_id].onboard_language_for_codeql_bulk_building(language)
      end
    end
  end
end
