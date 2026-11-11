# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This module allows Hydro jobs to wait for defined replicas
#
# Example:
#
#   class HydroMyJob < HydroMessageJob
#     include HydroWaitForReplicasTrait
#
#     wait_for_replicas ApplicationRecord::Mysql1,
#       ApplicationRecord::Repositories
#
#     def perform
#       # work
#     end
#   end
#
# Passing :none means the job does not need to wait for
# replication on any cluster:
#
#   wait_for_replicas :none
#
# Note that this only changes the replicas the job waits for, it
# doesn't force connections to be only against those replicas
module HydroWaitForReplicasTrait
  extend T::Helpers

  requires_ancestor { HydroMessageJob }

  module ClassMethods
    extend T::Helpers

    def wait_for_replicas(*replicas)
      @replica_clusters_declared = true
      return if replicas == [:none]
      @replica_clusters ||= []
      @replica_clusters.concat(replicas)
    end

    def replica_clusters
      @replica_clusters ||= []
    end

    def replica_clusters_declared?
      !!@replica_clusters_declared
    end
  end

  mixes_in_class_methods(ClassMethods)

  # This module overrides HydroMessageJob#tracked_replication_state method to make sure
  # the job only waits on the replicas defined with .wait_for_replicas
  def tracked_replication_state
    replication_state = super
    # If wait_for_replicas was never called, fall back to default behavior (wait on all clusters).
    return super unless T.cast(self.class, ClassMethods).replica_clusters_declared?

    replica_names = T.cast(self.class, ClassMethods).replica_clusters.map(&:cluster_name).to_set
    replication_state.to_hash.select { |k, _| replica_names.include?(k) }
  end
end
