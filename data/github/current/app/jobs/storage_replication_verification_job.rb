# typed: true
# frozen_string_literal: true

# This job gets queued from StorageClusterMaintenanceSchedulerJob.perform via ReplicaVerifier.perform
class StorageReplicationVerificationJob < ApplicationJob
  queue_as :storage_cluster

  locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: ->(job) { job.class.lock(*job.arguments) }

  class NoGoodReplicasError < ::StandardError; end

  retry_on Faraday::ConnectionFailed, Faraday::TimeoutError, wait: :polynomially_longer, attempts: 10

  def self.enabled?
    GitHub.enterprise?
  end

  def self.lock(options)
    options["oid"]
  end

  def perform(options = {})
    oid, hosts = options["oid"], options["hosts"]
    replicas = GitHub::Storage::Replica.get_replicas_for_oid(oid, hosts)

    # If there are no online replicas, then there's nothing we can do.  The
    # StorageReplicateJob will fix this if one of them comes online in the
    # future.
    return if replicas.empty?

    missing = replicas.select { |(host)| !GitHub::Storage::Client.has_object?(host, oid) }

    # Don't delete all replicas of an object.
    if missing.length == replicas.length
      raise NoGoodReplicasError, "no good replicas for #{oid}"
    elsif !missing.empty?
      missing.each { |(host)| prune_replica(host, oid) }

      # Kick off jobs for all.  If one isn't needed, it will do nothing.
      GitHub::Storage::Allocator.get_non_voting_datacenters.each do |dc|
        StorageReplicateObjectJob.perform_later({ "oid" => oid, "non_voting" => true, "datacenter" => dc })
      end
      StorageReplicateObjectJob.perform_later({ "oid" => oid, "non_voting" => false })
    end
  end

  def prune_replica(host, oid)
    blob = Storage::Blob.where(oid: oid).first
    return unless blob
    replica = blob.storage_replicas.where(host: host).first
    with_write { replica&.destroy }
  end
end
