# typed: true
# frozen_string_literal: true

class BillingSettings::OverviewView
  class SharedStorageUsage
    delegate_missing_to :usage
    attr_reader :account

    def initialize(account, usage:)
      @account = account
      @usage = usage
    end

    def has_error?
      usage.has_error?
    end

    def estimated_monthly_private_gigabytes
      to_gigabytes(usage.estimated_monthly_private_megabytes)
    end

    def estimated_monthly_paid_gigabytes
      to_gigabytes(usage.estimated_monthly_paid_megabytes)
    end

    def plan_included_megabytes
      included_usage = to_gigabytes(account.plan.shared_storage_included_megabytes)
      [estimated_monthly_private_gigabytes, included_usage].min
    end

    def plan_included_megabytes_in_gigabytes
      to_gigabytes(account.plan.shared_storage_included_megabytes)
    end

    private

    def to_gigabytes(size_in_megabytes)
      (size_in_megabytes.megabytes / 1.gigabyte.to_f).round(2)
    end

    attr_reader :usage
  end
end
