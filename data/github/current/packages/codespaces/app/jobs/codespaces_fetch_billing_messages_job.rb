# typed: true
# frozen_string_literal: true

class CodespacesFetchBillingMessagesJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # sequence_number is used here to leverage `DEFAULT_LOCK_PROC` locking of concurrent job execution by arguments.
  # In this case we want N jobs to be enqueued to process a specific billing message queue without duplicating a
  # sequence_number
  def perform(azure_storage_account_name:, environment: :production, sequence_number: 1)
    # This flag can be turned on to disable processing of billing messages.
    return if with_read { GitHub.flipper[:codespaces_disable_billing_jobs].enabled? }

    if Codespaces::Billing::FetchMessages.call(azure_storage_account_name: azure_storage_account_name, environment: environment)
      # clear the lock on this job/azure_storage_account_name so we can re-enqueue another job
      clear_lock

      # enqueue a new CodespacesFetchBillingMessagesJob to continue processing
      CodespacesFetchBillingMessagesJob.perform_later(
        azure_storage_account_name: azure_storage_account_name,
        sequence_number: sequence_number,
        environment: environment
      )
    end
  end
end
