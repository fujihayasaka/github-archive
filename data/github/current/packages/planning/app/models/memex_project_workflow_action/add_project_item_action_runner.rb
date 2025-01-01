# typed: true
# frozen_string_literal: true

# This class is a scaffold for testing the piped workflow runner, will be fleshed out in a future PR
class MemexProjectWorkflowAction::AddProjectItemActionRunner < MemexProjectWorkflowAction::BaseActionRunner
  ACTION_TYPE = :add_project_item

  def run
    log_duration do
      add_items
    end
  end

  private

  def add_items
    items = []
    # copy pasta from app/jobs/memex_bulk_add_job.rb
    memex_project = @action.workflow.memex_project
    @input.each_slice(BATCH_SIZE) do |batch|
      MemexProject.throttle do
        batch.each do |issue_or_pull|
          # todo #projects-automation: skip if item already exists in project
          begin
            with_write do
              item = memex_project.build_item(issue_or_pull: issue_or_pull, creator: Apps::Internal::MemexAutomation.bot)
              memex_project.save_with_priority!(item, **{ position: :bottom })
              items << item
            end
          # this should catch all validation errors including duplicate item creation
          rescue ActiveRecord::RecordInvalid => e
            log_action_skipped(**log_payload(input: [issue_or_pull], reason: REASON_RECORD_INVALID))
            log_error(e)
            next
          # we are seeing the following error in production, although in tests it is always cought by the invalid record validation
          rescue ActiveRecord::RecordNotUnique => e
            log_action_skipped(**log_payload(input: [issue_or_pull], reason: REASON_EXISTS))
            log_error(e)
            next
          end
        end
      end
    end

    items
  end

  def log_error(exception)
    GitHub.logger.error(
      exception,
      "error.context": "could not add item to project performed through workflow action",
      "code.namespace": self.class
    )
  end
end
