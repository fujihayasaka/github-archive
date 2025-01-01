# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class MemexUnarchiveItemsJob < ApplicationJob
  BATCH_SIZE = 100
  MAX_ATTEMPTS = 5

  queue_as :memex_unarchive_items

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

    flag_as_bulk_operation = GitHub.flipper[:memex_flag_bulk_archive_operations].enabled?
    status = Memex::JobStatus.find!(job_id)
    with_write do
      status.started!
    end

    batch_ids = item_ids.shift(BATCH_SIZE)
    MemexProjectItem.throttle do
      viewable_items, unviewable_items = memex_project.partition_items_by_readability(current_user, batch_ids)
      if unviewable_items.any?
        GitHub.logger.info(
          "Unable to unarchive items due to insufficient permissions",
          "code.namespace" => self.class.name,
          "gh.actor.id" => current_user_id,
          "gh.memex.project.id" => memex_id,
          "gh.memex.unauthorized_item_ids" => unviewable_items.map(&:id)
        )
      end
      if viewable_items.any?
        unarchived_item_ids = []
        with_write do
          viewable_items.each do |item|
            begin
              item.unarchive!(bulk_operation: flag_as_bulk_operation)
              unarchived_item_ids << item.id
            rescue StandardError => e
              Failbot.report(e)
            end
          end
        end

        if unarchived_item_ids.present?
          GlobalInstrumenter.instrument("memex_project_item.bulk_unarchive", {
            actor: current_user,
            project: memex_project,
            item_ids: unarchived_item_ids,
            request_context:,
          })
        end
      end
    end

    if item_ids.any?
      MemexUnarchiveItemsJob.perform_later(job_id, item_ids, current_user_id, memex_id, request_context:)
    else
      with_write do
        status.success!
      end
    end
  end
end
