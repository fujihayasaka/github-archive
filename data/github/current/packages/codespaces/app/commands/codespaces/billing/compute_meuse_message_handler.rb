# typed: true
# frozen_string_literal: true

class Codespaces::Billing::ComputeMeuseMessageHandler < Codespaces::Billing::MeuseMessageHandler
  include Codespaces::UniqueCodespaceBillingIdentifierHelper

  private

  def post_transform_usage
    custom_fields = {}
    {
      actor_id: billing_entry.codespace_owner&.id,
      quantity: tracked_usage.billable_duration_in_hours,
      custom_fields: custom_fields,
    }
  end

  def unique_billing_identifier
    unique_identifier("Codespaces/Compute/")
  end

  def pre_should_publish?
    return false unless tracked_usage.is_compute?
    return false if tracked_usage.sku && tracked_usage.sku.unbillable?

    unless tracked_usage.sku.present? && product_sku_name.present?
      Failbot.report(ArgumentError.new("Unknown SKU '#{tracked_usage.sku_name}'"))
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

  def product_sku_name
    if [2, 4, 8, 16, 32].include?(tracked_usage.sku&.cpus)
      "compute_d#{tracked_usage.sku.cpus}".to_sym
    end
  end

  def post_perform
    notify_later_if_applicable
    check_usage_limit
  end

  def notify_later_if_applicable
    # We call this job in compute only, rather than storage or prebuild usage etc, because we want to send the
    # notification to codespaces that are actively running (consuming compute) so that the user can see the
    # notification in VSCode. We don't want to send the notif to codespaces that are stopped, because the user won't see it.
    Codespaces::VscodeBillingThresholdNotifierJob.set(wait: POST_PERFORM_JOBS_DELAY).perform_later(
      billable_owner: billing_entry.billable_owner,
      codespace: billing_entry.codespace
    )
  end

  def check_usage_limit
    codespace = billing_entry.codespace

    return if codespace.nil?

    Codespaces::SuspendCodespaceAtUsageLimitJob.set(wait: POST_PERFORM_JOBS_DELAY).perform_later(
      codespace: codespace
    )
  end

  def publish_usage(billing_data)
    Codespaces::BillingMessageHandlerResult.new(hydro_topic: "meuse.metered_usage", hydro_payload: billing_data)
  end
end
