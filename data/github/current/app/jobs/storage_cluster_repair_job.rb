# typed: true
# frozen_string_literal: true

class StorageClusterRepairJob < ApplicationJob
  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  queue_as :storage_cluster

  def perform(backing_up)
    SlowQueryLogger.disabled do
      GitHub::Storage::ClusterRepair.perform_voting(backing_up: backing_up)
      datacenters = GitHub::Storage::Allocator.get_non_voting_datacenters
      datacenters.each do |dc|
        GitHub::Storage::ClusterRepair.perform_non_voting(dc, backing_up: backing_up)
      end
      GitHub::Storage::ClusterRepair.perform_non_voting_cached(backing_up: backing_up)

      StorageClusterRebalancerJob.perform_later(backing_up)
    end
  end
end
