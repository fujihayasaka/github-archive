# typed: true
# frozen_string_literal: true

class MemexProjectWorkflowAction::GetSubIssuesActionRunner < MemexProjectWorkflowAction::BaseActionRunner
  ACTION_TYPE = :get_sub_issues

  def run
    log_duration do
      return @input unless @manual_run
      get_sub_issues_of_parents_in_project
    end
  end

  private

  sig { returns(T::Array[Issue]) }
  def get_sub_issues_of_parents_in_project
    memex_project = @action.workflow.memex_project

    project_issues = memex_project
      .memex_project_items
      .not_archived
      .preload(:content)
      .where(content_type: MemexProjectItem::ContentType::Issue.serialize)
      .map(&:content).compact # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    project_issues = T.cast(project_issues, T::Array[Issue])

    GitHub::PrefillAssociations.prefill_associations(project_issues, :sub_issues) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    project_issues.flat_map(&:sub_issues).compact
  end
end
