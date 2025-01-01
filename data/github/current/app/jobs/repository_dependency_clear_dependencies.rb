# typed: true
# frozen_string_literal: true

class RepositoryDependencyClearDependencies < ApplicationJob
  queue_as :repository_dependencies
  retry_on_dirty_exit
  include Repositories::Domain::Provider

  def perform(repository_id)
    repository = repositories_domain.by_id(repository_id, allow_deleted: true)
    return false if repository.nil?

    DependencyGraph::CrossServiceJob.enqueue(job_class: "ClearDependenciesJob", args: [repository.id])
    true
  end
end
