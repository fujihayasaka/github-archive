# typed: true
# frozen_string_literal: true

class Codespaces::Billing::ComputeVNextMessageHandler < Codespaces::Billing::VNextMessageHandlerBase
  POST_PERFORM_JOBS_DELAY = 15.minutes

  private

  def post_perform
    check_usage_limit
  end

  def check_usage_limit
    codespace = billing_entry.codespace

    return if codespace.nil?

    Codespaces::SuspendCodespaceAtUsageLimitJob.set(wait: POST_PERFORM_JOBS_DELAY).perform_later(
      codespace: codespace
    )
  end

  def unique_billing_identifier
    unique_identifier("Codespaces/Compute/")
  end

  def pre_should_publish?
    return false unless tracked_usage.is_compute?
    return false if tracked_usage.sku && tracked_usage.sku.unbillable?

    unless tracked_usage.sku.present? && billing_sku.present?
      Failbot.report(ArgumentError.new("Unknown SKU '#{tracked_usage.formatted_sku_name}'"))
      return false
    end

    # If the codespace was deprovisioned, we've already validated that it occurred during the billable window
    if billing_entry.codespace.nil?
      return false unless billing_entry.codespace_deprovisioned_at.present?
    else
      return false unless billing_entry.codespace.accessible?
    end
    return false unless tracked_usage.billable_duration_in_seconds.positive?
    true
  end

  def billing_sku
    sku = "codespaces_compute_d#{tracked_usage.sku.cpus}" if tracked_usage.sku
    return nil unless Codespaces::Billing::BillingPlatform::COMPUTE_SKUS.include?(sku)
    sku
  end

  def quantity
    tracked_usage.billable_duration_in_hours
  end

  def actor_id
    billing_entry.codespace_owner_id
  end
end
