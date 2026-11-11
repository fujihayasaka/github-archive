# typed: true
# frozen_string_literal: true

class Businesses::BillingSettings::ShowView
  class AssetStatusUsage
    attr_reader :organization
    delegate :bandwidth_usage, :bandwidth_quota, :storage_usage, :storage_quota, to: :asset_status

    def initialize(organization, asset_status:)
      @organization = organization
      @asset_status = asset_status
    end

    private

    attr_reader :asset_status
  end
end
