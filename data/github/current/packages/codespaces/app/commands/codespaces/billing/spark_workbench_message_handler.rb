# typed: true
# frozen_string_literal: true

class Codespaces::Billing::SparkWorkbenchMessageHandler < Codespaces::Command
  attr_reader :billing_message, :tracked_usage, :billing_entry

  def initialize(billing_message:, tracked_usage:, billing_entry:)
    @billing_message = billing_message
    @tracked_usage = tracked_usage
    @billing_entry = billing_entry
  end

  def perform
    return unless should_publish?

    send_workbench_telemetry_event

    payload = {
      owner: billing_entry.codespace_owner,
      billable_owner: billing_entry.billable_owner,
      codespace_guid: billing_entry.codespace_guid,
      spark_workbench_id: billing_entry.spark_workbench_id,
      usage_seconds: tracked_usage.billable_duration_in_seconds,
      start_at: billing_message.period_start,
      end_at: billing_message.period_end,
    }
    Codespaces::SparkWorkbenchUsageMessageHandlerResult.new(payload)
  end

  private

  def send_workbench_telemetry_event
    payload = Workbench::TelemetryInstrumenter::Payload.new(
      context: {
        codespace_guid: billing_entry.codespace_guid,
        usage_seconds: tracked_usage.billable_duration_in_seconds,
        start_at: billing_message.period_start,
        end_at: billing_message.period_end,
      },
      event_time: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i, nanos: 0),
      event_type: Workbench::Events::DEV_COMPUTE_DURATION,
      request_id: "",
      session_id: "",
      spark_id: billing_entry.spark_workbench_id,
      user_analytics_tracking_id: billing_entry.codespace_owner.analytics_tracking_id,
      user_id: billing_entry.codespace_owner.id,
      restricted: false,
    )

    Workbench::TelemetryInstrumenter.instrument(payload)
  end

  def billing_billable_owner
    billing_entry.billable_owner&.billable_owner
  end

  def should_publish?
    # This will probably need to actually come directly from the billing entry itself for post-deletion usage messages
    return false unless billing_entry.for_spark_workbench?
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
