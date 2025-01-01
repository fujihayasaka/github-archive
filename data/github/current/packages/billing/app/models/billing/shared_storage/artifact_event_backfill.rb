# typed: true
# frozen_string_literal: true

# Backfills shared storage usage to our billing platform. This is a one-time operation that can be run to migrate
# customers over. To ensure both systems are up-to-date, we will aggregate all events prior the current day and then
# send individual events from today using the same `usage_uuid` value that actions is using. This will guarantee that we don't
# miss any events while also preventing double billing since `usage_uuid` must be unique.
module Billing::SharedStorage
  class ArtifactEventBackfill
    BACKFILL_KEY = "billing_platform_migration.backfill_completed_at"

    def initialize(billable_owner:, cutoff: Time.now.utc)
      @billable_owner = billable_owner
      @cutoff = cutoff

      raise ArgumentError, "Billable owner does not have a customer" unless @billable_owner.customer
      backfill_timestamp = Billing::Kv.store.get("#{BACKFILL_KEY}.#{billable_owner.customer.id}").value { nil }
      raise ArgumentError, "Billable owner has already been migrated" if backfill_timestamp
      raise ArgumentError, "Billable owner is not eligible for a migration" unless @billable_owner.customer.billing_platform_enabled_product&.actions?
    end

    def perform
      usages = CurrentUsage.where(billable_owner: @billable_owner).distinct.select(:owner_id, :repository_id)

      # Aggregate events prior to today as a lump sum per owner/repo
      usages.map(&:owner_id).uniq.each do |owner_id|
        ArtifactEvent.billable_events_by_repo_and_source(owner_id, @cutoff.end_of_day - 1.day).each do |(repo_id, source, _), size_in_bytes|
          next if source != Billing::SharedStorage::ArtifactEvent.sources[:actions]
          emit_usage_event_aggregate(owner_id, repo_id, size_in_bytes)
        end
      end

      # Send all events from today
      usages.each  { |u| emit_events_from_today(u) }

      # Set the backfill timestamp so we don't run this again
      ActiveRecord::Base.connected_to(role: :writing) do
        Billing::Kv.store.set("#{BACKFILL_KEY}.#{@billable_owner.customer.id}", @cutoff.beginning_of_day.iso8601)
      end
    end

    private

    def emit_events_from_today(usage)
      ArtifactEvent.where(owner_id: usage.owner_id, repository_id: usage.repository_id, effective_at: @cutoff.beginning_of_day..GitHub::Billing.now).find_in_batches do |events|
        events.each do |event|
          next unless event.actions_source?
          emit_usage_event(event)
        end
      end
    end

    # Emits events using a deterministic UUID to ensure idempotency
    def emit_usage_event_aggregate(owner_id, repository_id, size_in_bytes)
      # There's a known issue where duplicate remove events could cause a negative size in bytes. We can ignore those when aggrgating.
      return if size_in_bytes <= 0

      size_in_gib = size_in_bytes.fdiv(1.gigabyte)
      usage_uuid_unique_id = "Actions/backfill/#{owner_id}/#{repository_id}"

      usage_message = {
        sku: "actions_storage",
        quantity: size_in_gib,
        usage_at: @cutoff.beginning_of_day - 1.day,
        source_uri: "Actions/aggregate-backfill/#{owner_id}/#{repository_id}",
        usage_uuid: Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, usage_uuid_unique_id), # rubocop:disable GitHub/InsecureHashAlgorithm
        entity: {
          customer_id: @billable_owner.customer.id,
          organization_id: owner_id,
          repo_id: repository_id,
        },
      }
      publish(usage_message)
    end

    # Emits events using the same UUID as actions to guarantee idempotency.
    def emit_usage_event(event)
      size_in_bytes = event.remove_event? ? -event.size_in_bytes : event.size_in_bytes

      size_in_gib = size_in_bytes.fdiv(1.gigabyte)
      usage_uuid_unique_id = "Actions/#{event.source_artifact_id}/"

      event.add_event? ? usage_uuid_unique_id << "add" : usage_uuid_unique_id << "remove"

      usage_message = {
        sku: "actions_storage",
        quantity: size_in_gib,
        usage_at: event.created_at,
        source_uri: event.to_global_id.to_s,
        usage_uuid: Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, usage_uuid_unique_id), # rubocop:disable GitHub/InsecureHashAlgorithm
        entity: {
          customer_id: @billable_owner.customer.id,
          organization_id: event.owner_id,
          repo_id: event.repository_id,
        },
      }

      publish(usage_message)
    end

    def publish(message)
      if GitHub.flipper[:artifact_event_backfill_migration].enabled?
        Hydro::PublishRetrier.publish(message, schema: "billingplatform.v1.Usage", publisher: GitHub.hydro_publisher)
      end
    end
  end
end
