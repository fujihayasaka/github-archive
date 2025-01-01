# typed: true
# frozen_string_literal: true

class MemexProjectWorkflowAction::GetSubIssuesActionRunner < MemexProjectWorkflowAction::BaseActionRunner
  extend T::Sig
  ACTION_TYPE = :get_sub_issues

  def run
    log_duration do
      return @input unless @manual_run
      get_sub_issues_of_parents_in_project
    end
  end

  private

  sig { returns(T::Array[SubIssue]) }
  def get_sub_issues_of_parents_in_project
    memex_project = @action.workflow.memex_project

    project_issues = MemexProjectItem
      .preload(:content)
      .where(
        archived_at: nil,
        content_type: MemexProjectItem::ISSUE_TYPE,
        memex_project: memex_project,
      )
      .map(&:content).compact

    GitHub::PrefillAssociations.prefill_associations(project_issues, :sub_issues)

    project_issues.flat_map(&:sub_issues).compact
  end
end
