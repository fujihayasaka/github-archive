# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class MemexDestroyItemsJob < ApplicationJob
  BATCH_SIZE = 100
  MAX_ATTEMPTS = 5

  queue_as :memex_destroy_items

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on JobStatus::NotFound, wait: :polynomially_longer, attempts: MAX_ATTEMPTS # will retry 4 times over 6 minutes

  def self.prefix
    name
  end

  def self.create_job_status
    id = "#{prefix}:#{SecureRandom.uuid}"
    Memex::JobStatus.create(id:)
  end

  def perform(job_id, item_ids, current_user_id, memex_id, request_context: {})
    current_user = User.find_by(id: current_user_id)
    memex_project = MemexProject.find_by(id: memex_id)
    return unless current_user && memex_project

    status = Memex::JobStatus.find!(job_id)
    with_write do
      status.started!
    end

    batch_ids = item_ids.shift(BATCH_SIZE)
    MemexProjectItem.throttle do
      viewable_items, unviewable_items = memex_project.partition_items_by_readability(current_user, batch_ids)
      viewable_items.each do |item|
        # Setting this transient state on the item ultimately allows us to skip instrumentation of
        # individual delete events in favour of instrumenting a single bulk delete event later in
        # this job. This enables more efficient behaviour downstream.
        item.bulk_operation = true
      end
      destroyed, failed = with_write { viewable_items.partition(&:destroy) }

      if destroyed.any?
        GlobalInstrumenter.instrument("memex_project_item.bulk_delete", {
          actor: current_user,
          project: memex_project,
          item_ids: destroyed.map(&:id),
          issue_ids: destroyed.map(&:issue_id).compact,
          request_context:,
        })
      end

      if failed.any?
        log(
          "Unable to destroy items due to aborted callback",
          "gh.user.id": current_user_id,
          "gh.memex.project.id": memex_id,
          "gh.memex.item.ids": failed.map(&:id)
        )
      end

      if unviewable_items.any?
        log(
          "Unable to destroy items due to insufficient permissions",
          "gh.user.id": current_user_id,
          "gh.memex.project.id": memex_id,
          "gh.memex.item.ids": unviewable_items.map(&:id)
        )
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
