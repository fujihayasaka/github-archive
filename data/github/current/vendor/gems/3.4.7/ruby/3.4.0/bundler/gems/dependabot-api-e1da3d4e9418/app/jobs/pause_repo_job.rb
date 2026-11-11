# frozen_string_literal: true

class PauseRepoJob < ApplicationJob
  queue_as :pause_repo
  default_retries_for_idempotent_jobs

  PAUSE_AFFECTED_DOTCOM_CLUSTERS = %i(issues-pull-requests configurations).freeze

  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions:
        [
          GitHub::Twirp::DependabotRepositorySettings::Error,
          Freno::Throttler::WaitedTooLong,
        ],
    ),
  )

  AUDIT_LOG_ACTION = "dependabot_updates.repository_paused"

  def perform(repo_id:, event_source:)
    @repo = Repo.find_by(id: repo_id)
    return unless repo
    return if repo.paused?

    Dependabot.freno_throttler.throttle(PAUSE_AFFECTED_DOTCOM_CLUSTERS) do
      # dotcom will check if the repo is GHEC, and if so this method returns
      # false, we avoid pausing the repo and clear `will_pause_at` to avoid
      # attempting a pause again
      return repo.update!(will_pause_at: nil) unless pause_repo_on_dotcom.success

      repo.update!(paused_at: Time.current)
    end

    publish_audit_log_message(repo)
    repo.event_stream.record_event(Activity::RepoEvents::PAUSED, tags: { event_source: event_source })
    MetricsClient.increment("repository_paused", tags: { event_source: event_source })
  rescue GitHub::Twirp::DependabotRepositorySettings::NotFound => e
    deactivate_repo(reason: "repo_deleted", error_message: e.message)
  end

  private

  attr_reader :repo

  def pause_repo_on_dotcom
    Dependabot::Application.dependabot_repository_settings_client.set_paused_flag_on_repository(repo)
  end

  def publish_audit_log_message(repo)
    message = repo.audit_log_message(AUDIT_LOG_ACTION)

    Dependabot.hydro_publisher.batch do
      Dependabot.hydro_publisher.publish(message, schema: "hydro.schemas.audit_log.v2.AuditEntry")
    end
  end

  def deactivate_repo(reason:, error_message: nil)
    Dependabot::Logger.info(
      msg: "deactivate repo",
      "code.namespace": "PauseRepoJob",
      reason: reason,
      "exception.message": error_message,
      "gh.repo.id": repo.github_id,
    )
    DeactivateRepo.new(
      account: repo.account,
      repo_github_id: repo.github_id
    ).run
  end
end
