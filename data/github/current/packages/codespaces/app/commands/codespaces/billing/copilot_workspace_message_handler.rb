# typed: true
# frozen_string_literal: true

class Codespaces::Billing::CopilotWorkspaceMessageHandler < Codespaces::Command
  attr_reader :billing_message, :tracked_usage, :billing_entry

  def initialize(billing_message:, tracked_usage:, billing_entry:)
    @billing_message = billing_message
    @tracked_usage = tracked_usage
    @billing_entry = billing_entry
  end

  def perform
    return unless should_publish?

    payload = {
      owner: billing_entry.codespace_owner,
      billable_owner: billing_entry.billable_owner,
      codespace_guid: billing_entry.codespace_guid,
      copilot_workspace_id: billing_entry.copilot_workspace_id,
      usage_seconds: tracked_usage.billable_duration_in_seconds,
      start_at: billing_message.period_start,
      end_at: billing_message.period_end,
    }
    Codespaces::CopilotWorkspaceBillingMessageHandlerResult.new(payload)
  end

  private

  def billing_billable_owner
    billing_entry.billable_owner&.billable_owner
  end

  def should_publish?
    # This will probably need to actually come directly from the billing entry itself for post-deletion usage messages
    return false unless billing_entry.for_copilot_workspace? || billing_entry.for_workspace_editor?
    return false if billing_entry.for_spark_workbench?
    return false unless tracked_usage.is_compute?
    return false if tracked_usage.sku && tracked_usage.sku.unbillable?

    # If the codespace was deprovisioned, we've already validated that it occurred during the billable window
    if billing_entry.codespace.nil?
      return false unless billing_entry.codespace_deprovisioned_at.present?
    else
      return false unless billing_entry.codespace.accessible?
    end
    return false unless tracked_usage.billable_duration_in_seconds.positive?
    return false if billing_billable_owner.nil?
    true
  end
end
