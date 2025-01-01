# typed: true
# frozen_string_literal: true

class TransferDiscussionJob < ApplicationJob
  queue_as :transfer_discussion

  retry_on_dirty_exit

  # Discard the job if the subject or author are deleted before the job runs
  discard_on ActiveRecord::RecordNotFound

  def perform(discussion_transfer, staff_user: nil)
    # Nothing to do here
    return if discussion_transfer.done?

    transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(discussion_transfer)

    GitHub.context.push(actor_id: discussion_transfer.actor_id) do
      with_write do
        unless transferrer.complete_transfer(staff_user)
          GitHub.dogstats.increment("discussions.failed_transfer")

          unless transferrer.revert_started_transfer
            GitHub.dogstats.increment("discussions.failed_transfer_revert")
          end
        end
      end
    end
  end
end
