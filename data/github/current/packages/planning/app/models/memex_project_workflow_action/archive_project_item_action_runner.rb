# typed: true
# frozen_string_literal: true

class MemexProjectWorkflowAction::ArchiveProjectItemActionRunner < MemexProjectWorkflowAction::BaseActionRunner
  ACTION_TYPE = :archive_project_item

  def run
    log_duration do
      archive_items
    end
  end

  private

  def archive_items
    items = []
    @input.each_slice(BATCH_SIZE) do |batch|
      MemexProjectItem.throttle do
        batch.each do |project_item|
          with_write do
            next log_action_skipped(**log_payload(project_item: project_item, reason: REASON_ARCHIVED)) if project_item.archived?
            project_item.archive!(Apps::Privileged::MemexAutomation.bot)
            items << project_item
          end
        end
      end
    end

    items
  end
end
