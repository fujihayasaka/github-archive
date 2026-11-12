# frozen_string_literal: true

require "github_helpers"
require "dependabot/pull_request_creator/labeler"

# Updates the default_labels column the update configs for the given repo
class UpdateDefaultLabelsJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  # Retry over the next 2.5 hours, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions:
        [*GitHubHelpers::RETRYABLE_ERRORS, Octokit::Unauthorized],
    ),
    callback: proc do |exception, _|
      next unless exception.is_a?(Octokit::Unauthorized)

      uncache_installation_client
    end,
  )

  def perform(repo:, available_labels: nil)
    @repo = repo
    @available_labels = available_labels
    return unless repo.account.active?

    repo.update_configs.active.each do |uc|
      uc.default_labels = [
        dependencies_label,
        using_multiple_languages? ? language_label(uc) : nil,
      ].compact
      uc.save
    end
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: repo,
      event_source: "job.update_default_labels",
    ).run
  end

  private

  attr_reader :repo

  def dependencies_label
    regex = Dependabot::PullRequestCreator::Labeler::DEPENDENCIES_LABEL_REGEX

    @dependencies_label ||=
      available_labels.find { |l| l.match?(regex) } || "dependencies"
  end

  def language_label(update_config)
    label =
      Dependabot::PullRequestCreator::Labeler.
      label_details_for_package_manager(update_config.package_manager).
      fetch(:name)

    available_labels.find { |l| l.casecmp(label).zero? } || label
  end

  def using_multiple_languages?
    return @using_multiple_languages if defined?(@using_multiple_languages)

    @using_multiple_languages =
      repo.update_configs.active.count("DISTINCT package_manager") > 1
  end

  def available_labels
    @available_labels ||=
      GitHubHelpers.fetch_all_pages(
        client: installation_github_client,
        method: :labels,
        args: [repo.github_id, { per_page: 100 }],
        transform: ->(page) { page.data.map(&:name) },
      )
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.
      new(account: repo.account)
  end

  def uncache_installation_client
    GitHubHelpers.delete_cached_access_token_for(
      account: repo.account,
    )
    @installation_github_client = nil
  end
end
