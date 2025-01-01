# typed: true
# frozen_string_literal: true

class DependencyGraphManageOwnerDependenciesJob < ApplicationJob
  # for now, let's use the queue all other dg jobs use
  queue_as :repository_dependencies
  locked_by timeout: 5.minutes, key: ->(job) { job.arguments[0] }

  retry_on_dirty_exit

  BATCH_SIZE = 100

  def perform(owner_id, task:)
    job = case task
    when :redetect
      RepositoryDependencyManifestInitializationJob
    when :clear
      RepositoryDependencyClearDependencies
    else
      nil
    end

    return if job.nil?

    repos_to_redetect = Repository.where(owner_id: owner_id)

    repos_to_redetect.in_batches(of: BATCH_SIZE) do |batch|
      batch.each do |repo|
        job.perform_later(repo.id) if repo.dependency_graph_enabled?
      end
    end

  end
end
