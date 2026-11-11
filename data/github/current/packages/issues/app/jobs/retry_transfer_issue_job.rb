# typed: true
# frozen_string_literal: true

class RetryTransferIssueJob < ApplicationJob
  queue_as :retry_transfer_issue

  # Discard the job if the subject or author are deleted before the job runs
  discard_on ActiveRecord::RecordNotFound

  # Transfers stuck in "started" for longer than this are considered stale
  # and eligible for retry — provided the TransferIssueJob lock is no longer
  # held. TransferIssueJob has a 1-hour lock timeout, so anything beyond that
  # has likely lost its lock, but we verify explicitly before retrying.
  STARTED_STALE_AFTER = 1.hour

  def perform(old_repository_id, _staff_user = nil, options = {})
    errored = IssueTransfer.where(old_repository_id: old_repository_id, state: "errored")
    stale_started = IssueTransfer.where(old_repository_id: old_repository_id, state: "started")
      .where("updated_at < ?", STARTED_STALE_AFTER.ago)
    issue_transfers = errored.or(stale_started)
    issue_transfers.each do |issue_transfer|
      next if transfer_job_locked?(issue_transfer)

      if issue_transfer.old_issue
        issue_transfer.throttle_writes do
          issue_transfer.transfer!(create_labels_if_missing: create_labels_if_missing?(options))
        end
      else
        issue_transfer.throttle_writes do
          issue_transfer.retry_transfer
        end
      end
    end
  end

  private

  def create_labels_if_missing?(options)
    options[:create_labels_if_missing].present? && options[:create_labels_if_missing]
  end

  def transfer_job_locked?(issue_transfer)
    job = TransferIssueJob.new(issue_transfer)
    job.locked?
  rescue => e
    # If the lock check fails (e.g. Redis unavailable), err on the side of
    # caution and skip the retry — it will be picked up on the next run.
    Rails.logger.warn("Failed to check TransferIssueJob lock for transfer #{issue_transfer.id}: #{e.message}")
    true
  end
end
