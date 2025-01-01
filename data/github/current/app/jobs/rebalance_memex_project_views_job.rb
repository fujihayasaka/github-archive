# typed: true
# frozen_string_literal: true

class RebalanceMemexProjectViewsJob < ApplicationJob
  queue_as :rebalance_memex_project_views

  retry_on_dirty_exit

  locked_by timeout: 1.hour, key: ->(job) { job.arguments[0] }

  def perform(memex_project_id, _actor_id, options = {})
    return unless (memex_project = MemexProject.find_by(id: memex_project_id))
    with_write do
      memex_project.rebalance!(association: :memex_project_views)
    end
  end
end
