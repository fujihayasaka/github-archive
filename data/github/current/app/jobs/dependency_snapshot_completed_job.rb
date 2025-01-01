# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# DependencySnapshotCompletedJob's main goal is notifying the rest of gh/gh
#  that a dependency snapshot was completed.
class DependencySnapshotCompletedJob < ApplicationJob
  queue_as :repository_dependencies

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(repository_id, sha, options = {})
    repository = Repositories.domain.by_id(repository_id)
    return unless T.cast(repository, T.nilable(Repository))&.dependency_graph_enabled? # rubocop:todo GitHub/AvoidCast

    Dependabot.repository_manifests_changed(repository: repository, reason: :on_dependency_snapshot)
  end
end
