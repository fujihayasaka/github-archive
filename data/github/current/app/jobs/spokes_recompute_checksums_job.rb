# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

require "github/dgit/delegate"
require "github/dgit/error"
require "github/dgit/maintenance"

class SpokesRecomputeChecksumsJob < ApplicationJob
  queue_as :dgit_repairs

  locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  RETRYABLE_ERRORS = [
    ActiveRecord::ConnectionNotEstablished,
    ActiveRecord::StatementInvalid,
    ActiveRecord::QueryCanceled,
    SystemCallError, # Errno::ECONNREFUSED, Errno::ECONNRESET and friends

    Freno::Throttler::Error,
    Freno::Error,
    Freno::Throttler::WaitedTooLong
  ]

  # Retry indefinitely when the workers were killed
  # This is an alternative to `retry_on_dirty_exit` so the linting rule is disabled for this class
  retry_on Aqueduct::Worker::JobKilled, wait: 5.seconds, attempts: :unlimited

  # Retry on database issues. We expect to run this job when the database has missed a write, so it shouldn't be
  # unusual to find that it's still having problems.
  retry_on *RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 10

  resolve_tenant_context do |repo_id|
    Repositories::Public.resolve_tenant(id: repo_id)
  end

  def perform(repo_id, is_wiki)
    Failbot.push app: "github-dgit"

    repo = find_repo(repo_id)
    Failbot.push spec: repo.dgit_spec(wiki: is_wiki)

    GitHub.logger.with_named_tags("gh.spokes.spec" => repo.dgit_spec(wiki: is_wiki)) do
      GitHub.logger.info("start", "code.function" => "perform!")
      perform!(repo_id, is_wiki)
    end
  end

  def perform!(repo_id, is_wiki)
    repo = find_repo(repo_id)

    GitHub::DGit::Maintenance.recompute_checksums(repo, :vote, is_wiki: is_wiki)
  end

  def find_repo(repo_id)
    repo = Repository.find_by_id(repo_id)
    raise GitHub::DGit::ChecksumInitError, "Repo ID #{repo_id} not found" unless repo
    repo
  end
end
