# typed: true
# frozen_string_literal: true

require_relative "../public/codespaces/error"
require_relative "../clients/codespaces/client"

class CodespacesFetchBillingStorageAccountNamesDevJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
  schedule interval: 10.minutes, condition: -> { !GitHub.enterprise? }

  retry_on Codespaces::Client::TimeoutError, wait: :polynomially_longer, attempts: 5 # will retry 4 times over 6 minutes
  retry_on_dirty_exit

  # Billing reporting operates at the stamp level, not the tenant level
  exempt_from_tenant_context_requirement

  VSCS_TARGET = :development

  def perform
    # This flag can be turned on to disable processing of billing messages.
    return if FeatureFlag.vexi.enabled_or_raise?(:codespaces_disable_billing_jobs) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    # we also want to be able to disable this particular job
    return if FeatureFlag.vexi.enabled_or_raise?(:codespaces_disable_billing_jobs_dev) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    storage_accounts = if FeatureFlag.vexi.enabled?(:codespaces_billing_rework, default: false)
      plan = Codespaces::Plan.for_storage_accounts(VSCS_TARGET)
      return if plan.nil?
      Codespaces::VscsClient.fetch_storage_accounts_and_tokens(plan: plan)
    else
      Codespaces::VscsClient.fetch_storage_accounts_and_tokens(vscs_target: VSCS_TARGET)
    end

    storage_accounts.each_key do |azure_storage_account_name|
      # Process queues seperately for each storage account so failing queues are isolated
      CodespacesFetchBillingStorageAccountJob.perform_later(azure_storage_account_name: azure_storage_account_name, environment: VSCS_TARGET)
    end
  end
end
