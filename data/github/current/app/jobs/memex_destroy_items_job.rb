# typed: true
# frozen_string_literal: true

class MemexDestroyItemsJob < ApplicationJob
  BATCH_SIZE = 100
  MAX_ATTEMPTS = 5

  queue_as :memex_destroy_items

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on JobStatus::NotFound, wait: :polynomially_longer, attempts: MAX_ATTEMPTS # will retry 4 times over 6 minutes

  def perform(job_id, item_ids, current_user_id, memex_id, request_context: {})
    current_user = User.find_by(id: current_user_id)
    memex_project = MemexProject.find_by(id: memex_id)
    return unless current_user && memex_project

    status = JobStatus.find!(job_id)
    with_write do
      status.started!
    end

    batch_ids = item_ids.shift(BATCH_SIZE)
    MemexProjectItem.throttle do
      viewable_items, unviewable_items = memex_project.partition_items_by_readability(current_user, batch_ids)
      if unviewable_items.any?
        log(
          "Unable to destroy items due to insufficient permissions",
          "gh.user.id": current_user_id,
          "gh.memex.project.id": memex_id,
          "gh.memex.item.ids": unviewable_items.map(&:id)
        )
      end
      if viewable_items.any?
        with_write do
          MemexProjectItem.where(id: viewable_items.map(&:id)).destroy_all
        end
      end
    end

    if item_ids.any?
      MemexDestroyItemsJob.perform_later(job_id, item_ids, current_user_id, memex_id, request_context:)
    else
      with_write do
        status.success!
      end
    end
  end

  private

  def log(msg, **kwargs)
    GitHub.logger.info(msg, {
      "code.namespace": self.class.name
    }.merge(kwargs))
  end
end
