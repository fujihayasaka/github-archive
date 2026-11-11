# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# DependencySnapshotCompletedJob's main goal is notifying the rest of gh/gh
#  that a dependency snapshot was completed.
class DependencySnapshotCompletedJob < ApplicationJob
  queue_as :repository_dependencies

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(repository_id, sha, snapshot_id: nil, ref: nil, detector_name: nil, correlator: nil, scanned_at: nil, created_at: nil, snapshot_type: nil, deadline: nil, dependency_change: nil)
    repository = Repositories::Public.get_active_or_deleted(repository_id)
    return unless repository
    return unless repository.dependency_graph_enabled?
    return if dependency_change == false

    if snapshot_type == :SNAPSHOT_TYPE_DEPENDABOT
      # Dependabot snapshots are normally handled via on_push/on_init alerting.
      # If the snapshot arrived after its deadline, the original event already
      # proceeded without it — trigger on_dependency_snapshot as a fallback so
      # alerting self-heals.
      return unless deadline.present? && deadline.past?
    end

    Dependabot.repository_manifests_changed(repository: repository, reason: :on_dependency_snapshot)
  end
end
