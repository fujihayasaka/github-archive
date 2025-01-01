# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ContributionsBackfillJob < ApplicationJob
  queue_as :contributions_backfill

  retry_on GitHub::Restraint::UnableToLock, wait: :polynomially_longer

  # How many concurrent jobs with the same key are allowed. Since this is
  # backfilling contributions for an entire repository, only one at a time
  # per repository, please:
  RUNNING_JOBS_PER_KEY = 1

  # How long a running (or crashed) job is allowed to hold onto a lock, in
  # seconds, before it expires and another one takes over.
  JOB_LOCK_TTL = 10.minutes

  resolve_tenant_context do |repo_id|
    Repositories::Public.resolve_tenant(id: repo_id)
  end

  def perform(repo_id, reset = false)
    repo = ActiveRecord::Base.connected_to(role: :reading) { Repositories.domain.by_id(repo_id) }
    return if repo.nil?

    key = ["contrib-backfill", repo.id].join(":")
    ContributionsBackfillJob.restraint.lock!(key, RUNNING_JOBS_PER_KEY, JOB_LOCK_TTL) do
      with_write do
        CommitContribution.backfill!(repo, reset)
      end
    end
  rescue ::GitRPC::InvalidRepository
    # The repository either doesn't exist yet or has been deleted. Either way
    # we should behave as though we hadn't found the repository in the database.
    nil
  end

  def logging_context
    super.merge({
      "gh.repo.id": repo_id,
    })
  end

  def failbot_context
    super.merge({
      "gh.repo.id": repo_id,
    })
  end

  def repo_id
    arguments.first
  end

  # Internal: a concurrency restraint using redis
  def self.restraint
    @restraint ||= GitHub::Restraint.new
  end
end
