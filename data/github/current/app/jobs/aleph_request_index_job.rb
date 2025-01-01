# typed: true
# frozen_string_literal: true

class AlephRequestIndexJob < ApplicationJob
  queue_as :aleph_request_index
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # Ensure that only one request index occurs per repo/commit_oid/reason within a 1 hour window.
  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  def perform(repo_id, commit_oid, reason)
    repo = Repository.find_by(id: repo_id)
    return if repo.nil?

    GitHub::Aleph.request_index(repo: repo, commit_oid: commit_oid, reason: reason)
  end
end
