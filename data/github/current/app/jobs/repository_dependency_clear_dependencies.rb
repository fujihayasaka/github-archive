# typed: true
# frozen_string_literal: true

class RepositoryDependencyClearDependencies < ApplicationJob
  queue_as :repository_dependencies
  retry_on_dirty_exit

  def perform(repository_id)
    repository = Repositories.domain.by_id(repository_id)
    return false if repository.nil?

    DependencyGraph::CrossServiceJob.enqueue(job_class: "ClearDependenciesJob", args: [repository.id])
    true
  end
end
