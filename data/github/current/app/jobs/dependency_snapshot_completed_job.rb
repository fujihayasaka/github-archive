# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# DependencySnapshotCompletedJob's main goal is notifying the rest of gh/gh
#  that a dependency snapshot was completed.
class DependencySnapshotCompletedJob < ApplicationJob
  queue_as :repository_dependencies

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(repository_id, sha, snapshot_id: nil, ref: nil, detector_name: nil, correlator: nil, scanned_at: nil, created_at: nil, snapshot_type: nil)
    repository = Repositories::Public.get_active_or_deleted(repository_id)
    return unless repository
    return unless repository.dependency_graph_enabled?

    unless snapshot_type == :SNAPSHOT_TYPE_DEPENDABOT
      Dependabot.repository_manifests_changed(repository: repository, reason: :on_dependency_snapshot)
    end
  end
end
