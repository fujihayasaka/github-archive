# frozen_string_literal: true

class DeactivateRepoJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  def perform(repo_github_id:, user:, account: nil)
    DeactivateRepo.new(
      account: account,
      repo_github_id: repo_github_id,
      user: user,
    ).run
  end
end
