# typed: true
# frozen_string_literal: true

module TransferableIssue
  def is_transfer_in_progress?
    return @is_transfer_in_progress if defined? @is_transfer_in_progress
    @is_transfer_in_progress = async_is_transfer_in_progress?.sync
  end

  def async_is_transfer_in_progress?
    ::Platform::Loaders::ActiveRecord.load(::IssueTransfer, T.unsafe(self).id, column: :new_issue_id).then do |transfer|
      transfer.present? && transfer.state != "done"
    end
  end

  # Returns true if either new or old issue has a corresponding transfer that is not "done"
  def is_involved_in_current_transfer?
    return @is_involved_in_current_transfer if defined? @is_involved_in_current_transfer
    @is_involved_in_current_transfer = async_is_involved_in_current_transfer?.sync
  end

  def async_is_involved_in_current_transfer?
    async_is_being_transferred?.then do |is_being_transferred|
      next true if is_being_transferred
      async_is_transfer_in_progress?
    end
  end

  def is_being_transferred?
    return @is_being_transferred if defined? @is_being_transferred
    @is_being_transferred = async_is_being_transferred?.sync
  end

  def async_is_being_transferred?
    ::Platform::Loaders::ActiveRecord.load(::IssueTransfer, T.unsafe(self).id, column: :old_issue_id).then do |transfer|
      transfer.present? && transfer.state != "done"
    end
  end
end
