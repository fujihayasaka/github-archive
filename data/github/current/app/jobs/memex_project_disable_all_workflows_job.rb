# typed: true
# frozen_string_literal: true

# This job will disable all workflows associated with a project.
class MemexProjectDisableAllWorkflowsJob < ApplicationJob
  queue_as :memex_project_disable_workflows

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(memex_id)
    memex = MemexProject.find_by(id: memex_id)
    return unless memex

    MemexProjectWorkflow.throttle do
      with_write do
        memex.workflows.update_all(enabled: false)
      end
    end
  end
end
