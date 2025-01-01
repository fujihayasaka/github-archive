# typed: true
# frozen_string_literal: true

class CodespacesCleanupUnprocessedBillingMessagesJob < CodespacesJob
  MAX_RECORDS_TO_DELETE = 1_000
  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }
  retry_on_dirty_exit

  def perform
    with_write do
      deleted = Codespaces::UnprocessedBillingMessage.where("created_at < ?", 90.days.ago).limit(MAX_RECORDS_TO_DELETE).delete_all
      CodespacesCleanupUnprocessedBillingMessagesJob.perform_later if deleted == MAX_RECORDS_TO_DELETE
    end
  end
end
