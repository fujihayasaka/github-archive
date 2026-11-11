# typed: true
# frozen_string_literal: true

class Businesses::BillingSettings::ShowView
  class PackageUsage
    attr_reader :organization

    def initialize(organization, usage:)
      @organization = organization
      @usage = usage
    end

    def gigabytes_used
      usage.private_gigabytes_used
    end

    private

    attr_reader :usage
  end
end
