# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# DependencySnapshotCompletedJob's main goal is notifying the rest of gh/gh
#  that a dependency snapshot was completed.
class DependencySnapshotCompletedJob < ApplicationJob
  queue_as :repository_dependencies

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(repository_id, sha, options: {}, snapshot_id: nil, ref: nil, detector_name: nil, correlator: nil, scanned_at: nil, created_at: nil)
    repository = Repositories.domain.by_id(repository_id)
    return unless T.cast(repository, T.nilable(Repository))&.dependency_graph_enabled? # rubocop:todo GitHub/AvoidCast

    Dependabot.repository_manifests_changed(repository: repository, reason: :on_dependency_snapshot)

    if repository&.feature_flag_enabled?(:dependency_graph_license_compliance, default: false)
      GlobalInstrumenter.instrument("dependency_graph.snapshot_processed", {
        repository_id: repository_id,
        snapshot_id: snapshot_id,
        ref: ref,
        sha: sha,
        detector_name: detector_name,
        correlator: correlator,
        scanned_at: scanned_at,
        created_at: created_at
      })
    end
  end
end
