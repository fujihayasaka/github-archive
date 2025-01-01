# typed: true
# frozen_string_literal: true

class Businesses::BillingSettings::ShowView
  class SharedStorageUsage
    attr_reader :organization

    def initialize(organization, usage:)
      @organization = organization
      @usage = usage
    end

    def estimated_monthly_private_gigabytes_used
      to_gigabytes(usage.estimated_monthly_private_megabytes)
    end

    private

    def to_gigabytes(size_in_megabytes)
      (size_in_megabytes.megabytes / 1.gigabyte.to_f).round(2)
    end

    attr_reader :usage
  end
end
