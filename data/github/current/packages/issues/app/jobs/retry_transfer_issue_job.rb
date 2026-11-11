# typed: true
# frozen_string_literal: true

class RetryTransferIssueJob < ApplicationJob
  queue_as :retry_transfer_issue

  # Discard the job if the subject or author are deleted before the job runs
  discard_on ActiveRecord::RecordNotFound

  def perform(old_repository_id, staff_user, options = {})
    issue_transfers = IssueTransfer.where(old_repository_id: old_repository_id, state: "errored")
    issue_transfers.each do |issue_transfer|
      if issue_transfer.old_issue
        issue_transfer.throttle_writes do
          issue_transfer.transfer!(create_labels_if_missing: create_labels_if_missing?(options), staff_user: staff_user)
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
end
