# typed: true
# frozen_string_literal: true

class Codespaces::Billing::StorageMeuseMessageHandler < Codespaces::Billing::MeuseMessageHandler
  include Codespaces::UniqueCodespaceBillingIdentifierHelper

  private

  def post_transform_usage
    custom_fields = {}
    {
      actor_id: billing_entry.codespace_owner&.id,
      quantity: tracked_usage.computed_usage_in_gb_month,
      custom_fields: custom_fields,
    }
  end

  def unique_billing_identifier
    unique_identifier("Codespaces/Storage/")
  end

  def pre_should_publish?
    return false unless tracked_usage.is_storage?

    # If the codespace was deprovisioned, we've already validated that it occurred during the billable window
    if billing_entry.codespace.nil?
      return false unless billing_entry.codespace_deprovisioned_at.present?
    else
      return false unless billing_entry.codespace.accessible?
    end
    return false unless tracked_usage.size_in_bytes.positive?
    return false unless tracked_usage.billable_duration_in_seconds.positive?
    true
  end

  def product_sku_name
    "storage"
  end

  def publish_usage(billing_data)
    Codespaces::BillingMessageHandlerResult.new(hydro_topic: "meuse.metered_usage", hydro_payload: billing_data)
  end
end
