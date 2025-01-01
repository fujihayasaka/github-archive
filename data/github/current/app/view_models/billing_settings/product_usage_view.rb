# typed: true
# frozen_string_literal: true

class BillingSettings::ProductUsageView < BillingSettings::OverviewView

  def client
    if account.delegate_billing_to_business?
      @client ||= ::Billing::Api::ClientWrapper.new(billable_owner: account.billable_owner, owner: account)
    else
      @client ||= ::Billing::Api::ClientWrapper.new(billable_owner: account)
    end
  end

  def billable_owner
    account.billable_owner
  end

  def shared_storage_usage
    usage = Billing::SharedStorageUsage.usage_quote(account)
    SharedStorageUsage.new(account, usage: usage)
  end

  def codespaces_monthly_usage
    @_codespaces_monthly_usage ||= client.codespaces_monthly_usage
  end

  def usage_threshold_banners
    @usage_threshold_banners ||= Billing::Budget.products.values.map do |budget_group|
      Billing::UsageThresholdBanner.new(owner: account, actor: current_user, budget_group: budget_group.to_sym)
    end
  end
end
