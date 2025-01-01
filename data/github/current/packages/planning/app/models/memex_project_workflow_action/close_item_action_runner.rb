# typed: true
# frozen_string_literal: true

class MemexProjectWorkflowAction::CloseItemActionRunner < MemexProjectWorkflowAction::BaseActionRunner
  ACTION_TYPE = :close_item

  sig { returns(T::Array[T.any(Issue, PullRequest)]) }
  def run
    log_duration do
      raise NotImplementedError, "Manual run not implemented for close_item action" if @manual_run

      close_items
    end
  end

  private

  sig { returns(MemexProject) }
  def memex_project
    @action.workflow.memex_project
  end

  sig { params(item: MemexProjectItem).returns(String) }
  def closing_status_in_project(item)
    field_option_id = memex_project.status_column&.memex_project_column_values&.find_by(memex_project_item: item)&.value
    memex_project.status_column&.settings_options.find { |option| option["id"] == field_option_id }&.[]("name")
  end


  sig { returns(T::Array[MemexProjectItem]) }
  def close_items
    items = []

    @input.each_slice(BATCH_SIZE) do |batch|
      MemexProject.throttle do
        batch.each do |project_item|
          if project_item.content.nil? || project_item.content.is_a?(DraftIssue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
            log_action_skipped(**log_payload(input: [project_item], reason: REASON_DOES_NOT_HAVE_CONTENT))
            next
          end

          if project_item.content.is_a?(PullRequest)
            log_action_skipped(**log_payload(input: [project_item], reason: REASON_IS_NOT_AN_ISSUE))
            next
          end

          if !project_item.content.closable_by?(@actor)
            log_action_skipped(**log_payload(input: [project_item], reason: REASON_NO_ACCESS))
            next
          end

          # internal apps (eg like the MemexAutomation bot) cannot close issues/PRs directly without being installed,
          # so we skip closing issues in the case that the action was triggered by an internal app
          # for example, when status update is caused by the "item added to the project" automation workflow & attributed to memex automation bot
          if !@actor.bot? && project_item.content.state == "open"
            with_write do
              project_item.content.close(@actor, attributes: { performed_by_project_workflow_action_id: @action.id, closing_status_in_project: closing_status_in_project(project_item) }) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
            end
            items << project_item
          else
            log_action_skipped(**log_payload(input: [project_item], reason: REASON_CANNOT_BE_CLOSED))
          end
        end
      end
    end

    items
  end
end
