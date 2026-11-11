# frozen_string_literal: true

module Stafftools
  class ResyncAccountJob < ApplicationJob
    queue_as :default
    default_retries_for_idempotent_jobs

    T.unsafe(self).include ActiveJob::Retry.new(
      strategy: RateLimitBackoffStrategy.new(
        limit: 5,
        retryable_exceptions: [
          *GitHubHelpers::RETRYABLE_ERRORS,
          Octokit::Forbidden,
          Octokit::Unauthorized,
          Octokit::UnprocessableEntity,
        ],
      ),
      callback: proc do |exception, _|
        Dependabot::Logger.error(
          msg: "ResyncAccountJob raised a retryable exception",
          "code.namespace": self.class.name.to_s,
          "gh.owner.id": account.id,
          "exception.type": exception.class,
          "exception.message": exception.message,
        )
        next unless exception.is_a?(Octokit::Unauthorized)

        uncache_installation_client(account)
      end,
    )

    def perform(account:)
      @account = account
      Dependabot::Exceptions.push(
        "gh.owner.id": account.id,
      )
      SynchronizeAccountState.new(account: account, event_source: "stafftools_resync_account_job").run

      return unless account.reload.active?

      account.repos.pluck(:github_id).each { |github_id| enqueue_repo_job(account, github_id) }
    end

    private

    attr_reader :account

    def enqueue_repo_job(account, github_id)
      Stafftools::ResyncRepoJob.perform_later(account: account, github_id: github_id)
    end
  end
end
