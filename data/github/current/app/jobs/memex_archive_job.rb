# typed: true
# frozen_string_literal: true

class MemexArchiveJob < ApplicationJob
  BATCH_SIZE = 10
  MAX_ATTEMPTS = 5

  queue_as :memex_archive
  retry_on_dirty_exit
  retry_on JobStatus::NotFound, wait: :polynomially_longer, attempts: MAX_ATTEMPTS # will retry 4 times over 6 minutes

  def perform(job_id, item_ids, current_user_id, memex_id)
    current_user = User.find_by(id: current_user_id)
    memex_project = MemexProject.find_by(id: memex_id)
    return unless current_user && memex_project

    status = JobStatus.find!(job_id)

    status.track do
      item_ids.each_slice(BATCH_SIZE) do |batch_ids|
        MemexProject.throttle do
          with_read do
            @viewable_items, @unviewable_items = memex_project.partition_items_by_readability(current_user, batch_ids)
          end

          @unviewable_items.each do |item|
            log("Unable to archive item due to insufficient permissions", "gh.user.id": current_user_id, "gh.memex.project.id": memex_id, "gh.memex.item.id": item.id)
          end

          with_write do
            MemexProject.transaction do
              @viewable_items.each do |item|
                begin
                    item.skip_item_can_be_archived_validation = true
                    item.archive!(current_user)
                  end
                rescue ActiveRecord::RecordInvalid => e
                  Failbot.report e
              end
            end
          end
        end
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
