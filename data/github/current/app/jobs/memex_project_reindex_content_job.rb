# typed: true
# frozen_string_literal: true

# This job will renindex the search index content for memex items belonging to a project
class MemexProjectReindexContentJob < ApplicationJob
  queue_as :memex_project_reindex_content

  retry_on_dirty_exit

  METRIC_INDEX = "memex_project_reindex_content_job"

  BATCH_SIZE = 1000

  def perform(memex_id)
    memex = MemexProject.find_by(id: memex_id)
    return tag_404 unless memex

    log("status:200") do
      memex.memex_project_items.find_in_batches(batch_size: BATCH_SIZE) do |group|
        group.each(&:synchronize_content_search_index)
      end

      GitHub.logger.info("MemexProjectReindexContentJob successfully run", "gh.memex.project.id": memex_id)
    end

  end

  def tag_404
    log("status:404")
  end

  def log(tags)
    yield if block_given?

    GitHub.dogstats.increment(
      METRIC_INDEX,
      tags: [tags],
    )
  end
end
