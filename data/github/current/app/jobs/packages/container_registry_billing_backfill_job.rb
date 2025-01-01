# typed: true
# frozen_string_literal: true
#
# This is a background job that should be used to correct the CR storage usage for given namespaces (or all of them).
#
# This job was originally needed to backfill existing customers with storage billing data because we had not enabled
# billing initially for container registry. It can be repeatedly run on a namespace (or group of namespaces) and should
# always result the same. The job checks RMS and what is reported by billing, then creates a billing event to make billing
# match what is reported by RMS. This is similar to our billing reconciliate job for v1 docker.
#
# Possible case for adding this to staff tools later if we begin to see issues with drift in CR billing like we did with docker.

module Packages
  class ContainerRegistryBillingBackfillJob < ApplicationJob
    queue_as :container_registry_billing_backfill

    retry_on_dirty_exit
    discard_on ActiveRecord::RecordNotFound

    def perform(namespaces: [], effective_date:, dry_run: false)
      return unless GitHub.billing_enabled?

      rms = PackageRegistry::Twirp.metadata_client

      # Get all namespaces RMS knows about if no namespaces were given
      ns = namespaces.blank? ? rms.get_all_namespaces.namespaces : namespaces

      # Group the namespaces by billable entities and separate out the ones that do not belong to a business
      business_namespaces = {}
      indie_namespaces = []
      ns.each do |name|
        namespace = User.find_by_login(name)

        if namespace.business
          business_namespaces[namespace.business.id] = namespace.business.organizations
        else
          indie_namespaces.append(namespace)
        end

      end

      # Map namespaces to storage used in bytes, accounting for deduplication across businesses
      ns_storage = {}

      business_namespaces.each do |_, namespaces|
        storage = rms.get_storage_utilization(namespaces: namespaces.map(&:name), effective_date: effective_date)

        namespaces.each { |n| ns_storage[n] = storage.namespaces[n.name] || 0 }
      end

      indie_namespaces.each do |namespace|
        storage = rms.get_storage_utilization(namespaces: [namespace.name], effective_date: effective_date)

        ns_storage[namespace] = storage.namespaces[namespace.name] || 0
      end

      output_map = {} # for outputting the results of a dry run

      # For each namespace send an event reporting the amount of storage used
      ns_storage.each do |namespace, storage_bytes|
        # Get billable owner and check feature flags
        billable_owner_designator = ::Billing::MeteredBillingBillableOwnerDesignator.new(namespace)
        billable_owner = billable_owner_designator.billable_owner

        next if GitHub.flipper[:packages_skip_cr_billing].enabled?(billable_owner)
        next unless GitHub.flipper[:container_registry_billing].enabled?(billable_owner)

        current_usage = Billing::SharedStorage::ArtifactEvent.container_registry_billable_events_by_repo(owner_id: namespace.id, effective_at: effective_date)

        storage_delta = storage_bytes - current_usage
        event_type = (storage_delta > 0) ? :add : :remove

        unless storage_delta.zero?
          ::Billing::SharedStorage::ArtifactEvent.throttle_writes_with_retry(max_retry_count: 5) do
            event = ::Billing::SharedStorage::ArtifactEvent.new(
              owner_id: namespace.id,
              repository_id: nil,
              effective_at: Time.now,
              source: :ghcr,
              repository_visibility: :private,
              event_type: event_type,
              size_in_bytes: storage_delta.abs,
              source_artifact_id: nil,
            )

            output_map[namespace.name] = event

            event.save! unless dry_run
          end
        end

        return output_map if dry_run
      end
    end
  end
end
