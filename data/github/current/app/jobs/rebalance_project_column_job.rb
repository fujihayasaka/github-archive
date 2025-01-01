# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

class RebalanceProjectColumnJob < ApplicationJob
  queue_as :rebalance_project_column

  retry_on_dirty_exit

  # All RebalanceProjectColumn jobs are locked by their project column id.
  # No attempt will be made to enqueue a job that's already running and the
  # lock is checked before running the job.
  locked_by timeout: 1.hour, key: ->(job) {
    job.arguments[0]
  }

  def perform(project_column_id, actor_id, options = {})
    return unless project_column = ProjectColumn.find_by_id(project_column_id)

    Failbot.push("gh.projects.column.id": project_column_id)

    GitHub.context.push(actor_id: actor_id) do
      Audit.context.push(actor_id: actor_id) do
        with_write do
          project_column.rebalance!
        end
      end
    end
  end
end
