# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# StorageClusterMoveObjectJob moves an object from from_host to to_host.
#
# This job gets queued from StorageClusterMaintenanceSchedulerJob.perform via
# Rebalancer.perform & Rebalancer.perform_non_voting.
class StorageClusterMoveObjectJob < ApplicationJob
  queue_as :storage_cluster

  def perform(oid, from_host, to_host)
    ok, body = GitHub::Storage::Client.move_to(from_host, [{ oid: oid, fileservers: [to_host] }])
    if ok
      successes = body["objects"].find_all { |o| o["success"].size > 0 }
      with_write do
        ApplicationRecord::Domain::Storage.transaction do
          successes.each do |obj|
            received = obj["success"].map { |h| URI.parse(h).host }
            GitHub::Storage::Creator.create_replicas_for_oid(oid, received)
            GitHub::Storage::Creator.delete_replica_from_host(from_host, oid)
          end
        end
      end
    end
  end
end
