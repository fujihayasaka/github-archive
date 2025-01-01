# typed: true
# frozen_string_literal: true

class Codespaces::Billing::StorageVNextMessageHandler < Codespaces::Billing::VNextMessageHandlerBase

  private

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

  def billing_sku
    Codespaces::Billing::BillingPlatform::STORAGE_SKU
  end

  def quantity
    tracked_usage.computed_usage_in_gb_month
  end

  def actor_id
    billing_entry.codespace_owner_id
  end
end
