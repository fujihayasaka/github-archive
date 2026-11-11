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
    end

    def perform
      GitHub.dogstats.increment(
          "billing.shared_storage_job_called",
          tags: ["job:artifact_event_backfill_job"]
        )
    end

    private

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
          customer_id: @billable_owner.find_or_create_customer.id,
          organization_id: event.owner_id,
          repo_id: event.repository_id,
        },
      }

      publish(usage_message)
    end

    def publish(message)
      if FeatureFlag.vexi.enabled_or_raise?(:artifact_event_backfill_migration) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        Hydro::PublishRetrier.publish(message, schema: "billingplatform.v1.Usage", publisher: GitHub.hydro_publisher)
      end
    end
  end
end
