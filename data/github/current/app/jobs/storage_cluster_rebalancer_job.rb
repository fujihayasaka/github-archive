# typed: true
# frozen_string_literal: true

class StorageClusterRebalancerJob < ApplicationJob
  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  queue_as :storage_cluster

  def perform(backing_up)
    SlowQueryLogger.disabled do
      unless backing_up
        GitHub::Storage::Rebalancer.perform
        datacenters = GitHub::Storage::Allocator.get_non_voting_datacenters
        datacenters.each do |dc|
          GitHub::Storage::Rebalancer.perform_non_voting(dc)
        end
        datacenter_cache_locations = GitHub::Storage::Allocator.get_non_voting_datacenter_cache_locations
        datacenter_cache_locations.each do |dc, cache_location|
          GitHub::Storage::Rebalancer.perform_non_voting_cached(dc, cache_location)
        end
      end
    end
  end
end
