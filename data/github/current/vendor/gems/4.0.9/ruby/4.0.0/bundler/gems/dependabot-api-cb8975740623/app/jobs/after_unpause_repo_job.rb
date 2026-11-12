# frozen_string_literal: true

class AfterUnpauseRepoJob < ApplicationJob
  queue_as :unpause_repo
  default_retries_for_idempotent_jobs

  PAUSED_PR_LIMIT = 100

  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions:
        [
          *GitHubHelpers::RETRYABLE_ERRORS,
          Octokit::Unauthorized,
          GitHub::Twirp::DependabotRepositorySettings::Error,
          Freno::Throttler::WaitedTooLong,
        ],
    ),
    callback: proc do |exception, _|
      next unless exception.is_a?(Octokit::Unauthorized)

      uncache_installation_client
    end,
  )

  AUDIT_LOG_ACTION = "dependabot_updates.repository_unpaused"

  def perform(repo_id:)
    @repo = Repo.find_by(id: repo_id)
    return unless repo

    # Updating any PRs is costly, let's update the flag first
    # so we backoff and retry if there's a connectivity issue.
    remove_paused_flag_from_dotcom

    publish_audit_log_message(repo)
    MetricsClient.increment("repository_unpaused")
  end

  private

  attr_reader :repo

  def remove_paused_flag_from_dotcom
    Dependabot::Application.dependabot_repository_settings_client.remove_paused_flag_on_repository(repo)
  end

  def installation_github_client
    @installation_github_client ||= GitHubHelpers::ClientWithRetries.new(account: repo.account)
  end

  def uncache_installation_client
    GitHubHelpers.delete_cached_access_token_for(
      account: repo.account,
    )
    @installation_github_client = nil
  end

  def publish_audit_log_message(repo)
    message = repo.audit_log_message(AUDIT_LOG_ACTION)

    Dependabot.hydro_publisher.batch do
      Dependabot.hydro_publisher.publish(message, schema: "hydro.schemas.audit_log.v2.AuditEntry")
    end
  end
end
