# typed: true
# frozen_string_literal: true

class UpdateStoragePartitionsJob < ApplicationJob
  schedule interval: 15.minutes, condition: ->() { GitHub.storage_cluster_enabled? }

  queue_as :storage_cluster

  def perform
    errors = []
    GitHub::Storage::Allocator.all_hosts_with_partitions.each do |host, partitions|
      ok, stats = GitHub::Storage::Client.stats(host, partitions)
      if !ok
        errors << "host-error: #{host}, #{stats["message"]}"
        next
      end

      stats["partitions"].each do |partition, v|
        if v["error"].present?
          errors << "partition-error: #{host}, #{partition}, #{v["error"]}"
          next
        end

        updated = with_write do
          GitHub::Storage::Allocator.update_partition_usage(host, partition, v["disk_free"], v["disk_used"])
        end

        unless updated
          errors << "update-error: #{host}, #{partition}"
        end
      end
    end

    if errors.present?
      GitHub::Logger.log(method: __method__,
                         errors: errors)
      raise "Errors present"
    end
  end
end
