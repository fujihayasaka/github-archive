# typed: true
# frozen_string_literal: true

class StorageClusterMaintenanceSchedulerJob < ApplicationJob
  schedule interval: 2.minutes, condition: -> { GitHub.storage_cluster_enabled? }

  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  queue_as :storage_cluster

  def perform
    SlowQueryLogger.disabled do
      StorageClusterReplicaVerifierJob.perform_later(GitHub::Enterprise.backup_in_progress?)
    end
  end
end
