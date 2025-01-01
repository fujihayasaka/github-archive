# typed: true
# frozen_string_literal: true

class Codespaces::Billing::PrebuildStorageAnalyticsMessageHandler < Codespaces::Command
  include Codespaces::UniqueCodespaceBillingIdentifierHelper
  include GitHub::Memoizer

  attr_reader :billing_message, :tracked_usage, :billing_entry
  def initialize(billing_message:, tracked_usage:, billing_entry:)
    @billing_message = billing_message
    @tracked_usage = tracked_usage
    @billing_entry = billing_entry
  end

  def perform
    return unless tracked_usage.is_storage?
    publish_storage_usage(transform_storage_usage)
  end

  private

  memoize def transform_storage_usage
    storage_usage = {
      owner_id: billing_entry.billable_owner_id,
      actor_id: nil,
      billable_duration_in_seconds: tracked_usage.billable_duration_in_seconds,
      source_uri: billing_message.source_uri,
      start_time: billing_message.period_start,
      end_time: billing_message.period_end,
      unique_billing_identifier: prebuild_unique_identifier,
      repository: billing_entry.repository ? Hydro::EntitySerializer.repository(billing_entry.repository) : Hydro::EntitySerializer.null_repository(billing_entry.repository_id),
      sku: tracked_usage.formatted_sku_name,
      computed_usage: 0,
      size_in_bytes: tracked_usage.size_in_bytes,
      vscs_target: billing_message.vscs_target,
      accessible: nil,
      actor: nil,
      billing_plan_owner: Hydro::EntitySerializer.codespace_billable_owner(billing_entry.billable_owner),
      codespace_id: nil,
      codespace_database_id: nil,
      region: billing_message.location,
      storage_type: :PREBUILD,
    }

    storage_usage
  end

  def publish_storage_usage(billing_data)
    Codespaces::BillingMessageHandlerResult.new(
      hydro_topic: Codespaces::Events::BILLING_STORAGE_ANALYTICS,
      hydro_payload: { storage_data: billing_data }
    ).publish
  end
end
