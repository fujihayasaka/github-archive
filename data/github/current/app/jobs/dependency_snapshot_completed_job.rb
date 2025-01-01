# typed: true
# frozen_string_literal: true

# DependencySnapshotCompletedJob's main goal is notifying the rest of gh/gh
#  that a dependency snapshot was completed.
class DependencySnapshotCompletedJob < ApplicationJob
  queue_as :repository_dependencies

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  include Repositories::Domain::Provider

  def perform(repository_id, sha, options = {})
    repository = repositories_domain.by_id(repository_id, allow_deleted: true)
    return unless T.cast(repository, T.nilable(Repository))&.dependency_graph_enabled? # rubocop:todo GitHub/AvoidCast

    Dependabot.repository_manifests_changed(repository: repository, reason: :on_dependency_snapshot)
  end
end
