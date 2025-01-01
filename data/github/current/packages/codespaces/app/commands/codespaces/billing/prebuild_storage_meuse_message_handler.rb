# typed: true
# frozen_string_literal: true

class Codespaces::Billing::PrebuildStorageMeuseMessageHandler < Codespaces::Billing::MeuseMessageHandler
  include Codespaces::UniqueCodespaceBillingIdentifierHelper
  include GitHub::Memoizer

  private

  def post_transform_usage
    {
      quantity: tracked_usage.computed_usage_in_gb_month,
    }
  end

  def pre_should_publish?
    return false if FeatureFlag.vexi.enabled_or_raise?(:codespaces_prebuild_billing_free, billing_entry.billable_owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    return false if !tracked_usage.is_storage?
    return false unless tracked_usage.computed_usage_in_gb_month.positive?
    return false if !should_bill_for_region?
    true
  end

  def unique_billing_identifier
    prebuild_unique_identifier("Codespaces/PrebuildStorage/")
  end

  def publish_usage(tranformed_usage)
    Codespaces::BillingMessageHandlerResult.new(hydro_topic: "meuse.metered_usage", hydro_payload: tranformed_usage)
  end

  def product_sku_name
    "prebuild_storage"
  end

  def should_bill_for_region?
    geos_to_billable_regions.include?(billing_message.location)
  end

  # allows us to bill once per prebuild geo
  def geos_to_billable_regions
    Codespaces::Locations::Geo.public.map(&:primary_region).map(&:id)
  end
end
