# typed: true
# frozen_string_literal: true

class Codespaces::Billing::PrebuildStorageVNextMessageHandler < Codespaces::Billing::VNextMessageHandlerBase

  private

  def pre_should_publish?
    return false if FeatureFlag.vexi.enabled_or_raise?(:codespaces_prebuild_billing_free, billing_entry.billable_owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    return false if !tracked_usage.is_storage?
    return false unless tracked_usage.computed_usage_in_gb_month.positive?
    return false if !should_bill_for_region?
    true
  end

  def actor_id
    nil
  end

  def billing_sku
    Codespaces::Billing::BillingPlatform::PREBUILD_STORAGE_SKU
  end

  def quantity
    tracked_usage.computed_usage_in_gb_month
  end

  def unique_billing_identifier
    prebuild_unique_identifier("Codespaces/PrebuildStorage/")
  end

  def should_bill_for_region?
    # allows us to bill once per prebuild geo
    primary_regions = Codespaces::Locations::Geo.public.map(&:primary_region).map(&:id)
    primary_regions.include?(billing_message.location)
  end
end
