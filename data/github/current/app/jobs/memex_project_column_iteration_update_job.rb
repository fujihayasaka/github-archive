# typed: true
# frozen_string_literal: true

class MemexProjectColumnIterationUpdateJob < ApplicationJob
  queue_as :memex_project_column_iteration_update
  locked_by timeout: 1.hour, key: ->(job) { job.arguments[0] }

  retry_on_dirty_exit

  resolve_tenant_context do |column_id|
    column = MemexProjectColumn.find_by(id: column_id)
    column&.memex_project&.resolve_tenant
  end

  def perform(iteration_column_id)
    return tag_404 unless column = MemexProjectColumn.find_by(id: iteration_column_id)
    return tag_orphaned unless column.memex_project.present?

    log("status:200") do
      MemexProjectColumn.throttle do
        with_write do
          column.sync_iteration_column_completed_iterations
        end
      end
      GitHub.logger.info("MemexProjectColumnIterationUpdateJob successfully run", "gh.memex.column.id": iteration_column_id)
    end
  end

  def tag_404
    log("status:404")
  end

  def tag_orphaned
    log("status:orphaned")
  end

  def log(status)
    yield if block_given?

    GitHub.dogstats.increment(
      "memex_project_column_iteration_update_job",
      tags: [status],
    )
  end
end
