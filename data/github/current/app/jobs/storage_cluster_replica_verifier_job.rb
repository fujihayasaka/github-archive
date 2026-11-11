# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class StorageClusterReplicaVerifierJob < ApplicationJob
  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  queue_as :storage_cluster

  def perform(backing_up)
    SlowQueryLogger.disabled do
      GitHub::Storage::ReplicaVerifier.perform unless backing_up

      StorageClusterRepairJob.perform_later(backing_up)
    end
  end
end
