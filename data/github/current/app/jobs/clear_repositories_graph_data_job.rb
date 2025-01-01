# typed: true
# frozen_string_literal: true

class ClearRepositoriesGraphDataJob < ApplicationJob
  queue_as :clear_repositories_graph_data

  retry_on_dirty_exit

  BATCH_SIZE = 100

  MAX_RUNTIME = 60

  def perform(repo_ids)
    processed_record_ids = []
    end_at = Time.now.to_f + MAX_RUNTIME
    Repository.where(id: repo_ids).includes(:owner).find_in_batches(batch_size: BATCH_SIZE) do |batch|
      batch.each do |repo|
        if repo.owner
          GitHub::RepoGraph::GRAPH_NAMES.each do |graph_name|
            GitHub::RepoGraph.clear_cache(repo, graph_name)
          end
        end
        processed_record_ids.push(repo.id)
        if Time.now.to_f > end_at
          remaining_record_ids = repo_ids - processed_record_ids
          ClearRepositoriesGraphDataJob.perform_later(remaining_record_ids) if !remaining_record_ids.empty?
          return
        end
      end
    end
  end
end
