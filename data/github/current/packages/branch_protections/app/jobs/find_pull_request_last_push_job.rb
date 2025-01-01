# typed: true
# frozen_string_literal: true

class FindPullRequestLastPushJob < ApplicationJob
  queue_as :find_pull_request_last_push

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # Borrow the retryable exceptions from the orchestrations (used by RepositoryPushJob and others)
  retry_on *Orchestration::RETRYABLE_ERRORS, wait: 3.minutes, attempts: 2

  use_primaries ApplicationRecord::IssuesPullRequests

  use_replicas ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql1

  resolve_tenant_context do |pull_request|
    if repository = pull_request.repository
      Business.find_by(id: repository.tenant_id)
    end
  end

  # Ensure the job only runs one instance for a given pull request.
  locked_by timeout: 12.minutes, key: ->(job) {
    pull_request = job.arguments.first
    pull_request.id
  }

  def perform(pull_request)
    GitHub.dogstats.increment("repository_rules_engine.last_reviewable_push.performed_job")

    GitHub.dogstats.distribution_time("find_pull_request_last_push_job") do
      RuleEngine::PullRequestStrictReviewRule.last_reviewable_push(
        pull_request,
        pull_request.repository,
        Repositories.domain,
        call_origin: :find_last_push_job)
    end
  end
end
