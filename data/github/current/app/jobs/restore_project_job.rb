# typed: false
# frozen_string_literal: true

# Restores a project by moving an Archived::Project and its dependent
# records back into unarchived tables.
class RestoreProjectJob < ApplicationJob
  queue_as :archive_restore

  retry_on_dirty_exit

  # All RestoreProject jobs are locked by their project id. No attempt
  # will be made to enqueue a job that's already running and the lock is
  # checked before running the job.
  locked_by timeout: 1.hour, key: ->(job) {
    job.arguments[0]
  }

  def perform(project_id)
    return unless project = Archived::Project.find_by_id(project_id)

    with_write do
      project.restore
    end
  end
end
