# typed: true
# frozen_string_literal: true

class Codespaces::Billing::StorageVNextMessageHandler < Codespaces::Billing::VNextMessageHandlerBase

  private

  def unique_billing_identifier
    unique_identifier("Codespaces/Storage/")
  end

  def pre_should_publish?
    return skip_publishing("tracked_usage is not storage") unless tracked_usage.is_storage?

    # If the codespace was deprovisioned, we've already validated that it occurred during the billable window
    if billing_entry.codespace.nil?
      return skip_publishing("billing_entry.codespace_deprovisioned_at nil") unless billing_entry.codespace_deprovisioned_at.present?
    else
      return skip_publishing("billing_entry.codespace.accessible? false") unless billing_entry.codespace.accessible?
    end
    return skip_publishing("tracked_usage.size_in_bytes <= 0") unless tracked_usage.size_in_bytes.positive?
    return skip_publishing("tracked_usage.billable_duration_in_seconds <= 0") unless tracked_usage.billable_duration_in_seconds.positive?
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
