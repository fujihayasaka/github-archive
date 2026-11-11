# typed: true
# frozen_string_literal: true

class IssueTransfer::Batch
  attr_reader :issue_ids, :active_transfers, :concurrent_jobs_count, :old_repository, :new_repository, :actor

  def initialize(old_repository, new_repository, actor, concurrent_jobs_count)
    @issue_ids = []
    @active_transfers = []
    @concurrent_jobs_count = concurrent_jobs_count
  end

  def size
    issue_ids.size
  end

  def empty?
    issue_ids.empty?
  end

  def issues
    @issues ||= Issue.where(id: issue_ids).to_a
  end

  def transfers
    @transfers ||= IssueTransfer.where(old_issue_id: issue_ids).to_a
  end

  def finished?
    !transfers.any?
  end

  def can_enqueue_more?
    active_transfers.size < concurrent_jobs_count
  end

  def enqueue_next_transfer
    next_transfer = transfers.shift
    if next_transfer.present?
      t = enqueue_transfer(next_transfer)
      active_transfers << t unless t.nil?
    end
  end

  def enqueue_transfer(transfer)
    return if transfer.state == "done"
    return if transfer.state == "errored"

    transfer.old_issue.reload

    if transfer.old_issue.title.blank?
      transfer.old_issue.title = "Untitled"
      Rails.logger.info "Replaced blank title with 'Untitled' for issue id:#{transfer.old_issue_id}"
    end

    # TODO update to allow toggling this value, default to true for now.
    Issue.throttle_with_retry { transfer.async_transfer!(create_labels_if_missing: true) }

    transfer
  end

  def queue_full?
    refresh_active_transfers!
    active_transfers.size >= concurrent_jobs_count
  end

  def refresh_active_transfers!
    @active_transfers = IssueTransfer.where(id: active_transfers.map(&:id)).where("state != 'done' AND state != 'errored'").to_a
  end

  def has_active_transfers?
    refresh_active_transfers!
    active_transfers.any?
  end
end
