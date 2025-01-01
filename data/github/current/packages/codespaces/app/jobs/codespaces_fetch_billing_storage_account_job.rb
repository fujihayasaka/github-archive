# typed: true
# frozen_string_literal: true

class CodespacesFetchBillingStorageAccountJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(azure_storage_account_name:, environment:)
    Codespaces::Billing::FetchStorageAccountNames.call(azure_storage_account_name: azure_storage_account_name, environment: environment)
  end
end
