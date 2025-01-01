# typed: true
# frozen_string_literal: true

class Codespaces::Billing::ComputeAnalyticsMessageHandler < Codespaces::Command
  include Codespaces::UniqueCodespaceBillingIdentifierHelper
  include GitHub::Memoizer

  attr_reader :billing_message, :tracked_usage, :billing_entry
  def initialize(billing_message:, tracked_usage:, billing_entry:)
    @billing_message = billing_message
    @tracked_usage = tracked_usage
    @billing_entry = billing_entry
  end

  def perform
    return unless tracked_usage.is_compute?
    publish_compute_usage(transform_compute_usage)
  end

  private

  memoize def transform_compute_usage
    compute_usage = {
      owner_id: billing_entry.billable_owner_id,
      actor_id: billing_entry.codespace_owner_id,
      billable_duration_in_seconds: tracked_usage.billable_duration_in_seconds,
      source_uri: billing_message.source_uri,
      start_time: billing_message.period_start,
      end_time: billing_message.period_end,
      unique_billing_identifier: unique_identifier,
      repository: billing_entry.repository ? Hydro::EntitySerializer.repository(billing_entry.repository) : Hydro::EntitySerializer.null_repository(billing_entry.repository_id),
      sku: tracked_usage.formatted_sku_name,
      # computed_usage is returning the amount of hours of usage for a given sku. Due to a
      # billing subscription service limitation, we expand the computed_usage for non-basic SKUs
      # to match what it would be billed at per hour. See: https://github.com/github/codespaces/issues/3713
      computed_usage: 0.0,
      vscs_target: billing_message.vscs_target,
      accessible: !!billing_entry.codespace&.accessible?,
      cpu_core_count: Codespaces::Skus.sku_by_name(tracked_usage.sku_name).cpus,
      gpu_core_count: Codespaces::Skus.sku_by_name(tracked_usage.sku_name).gpus,
      actor: Hydro::EntitySerializer.user(billing_entry.codespace_owner),
      billing_plan_owner: Hydro::EntitySerializer.codespace_billable_owner(billing_entry.billable_owner),
      codespace_id: billing_entry.codespace_guid,
      codespace_database_id: billing_entry.codespace&.id,
      region: billing_entry.codespace&.location,
    }

    if billing_entry.codespace&.copilot_workspace?
      compute_usage[:copilot_workspace_id] = billing_entry.codespace.copilot_workspace_id
    end

    if billing_entry.codespace.nil? && deleted_codespace = Codespace.deleted.find_by(guid: billing_entry.codespace_guid)
      compute_usage[:codespace_database_id] = deleted_codespace.id
      compute_usage[:region] = deleted_codespace.location
    end

    compute_usage
  end

  def publish_compute_usage(billing_data)
    Codespaces::BillingMessageHandlerResult.new(
      hydro_topic: Codespaces::Events::BILLING_COMPUTE_ANALYTICS,
      hydro_payload: { compute_data: billing_data }
    ).publish
  end
end
