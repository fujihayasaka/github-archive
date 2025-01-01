# typed: true
# frozen_string_literal: true

class CreateIssueOrchestration < IssueOrchestration
  def only_save_on_orchestration_end? = true

  step :set_assignees do
    T.bind(self, CreateIssueOrchestration)
    return if issue.nil?
    return if data[:assignee_data].blank?

    if !data[:from_api]
      user_can_assign = T.must(issue).assignable_by?(actor: actor)
      return if !user_can_assign
    end

    assignees = []
    if assignee_login = data.dig(:assignee_data, :assignee)
      assignees = [User.find_by_login(assignee_login)]
    end

    if assignee_id = data.dig(:assignee_data, :assignee_id)
      assignees = [User.find_by(assignee_id)]
    end

    if user_assignee_ids = data.dig(:assignee_data, :user_assignee_ids)
      assignees = User.where(id: user_assignee_ids)
    end
    T.must(issue).skip_create_issue_orchestration = true
    T.must(issue).skip_update_issue_orchestration = true
    T.must(issue).assignees = assignees
    T.must(issue).assignments.each { |a| a.skip_touch_issue_updated_at = true }
    T.must(issue).save!
  end

  job_start

  step :instrument do
    T.bind(self, CreateIssueOrchestration)
    return if issue.nil?

    T.must(issue).instrument_creation_event(body_template_name: data[:body_template_name])
  end

  step :clear_contributions_cache do
    T.bind(self, CreateIssueOrchestration)
    return if issue.nil?

    T.must(issue).clear_contributions_cache(context: "create_issue_orchestration")
  end

  step :synchronize_search_index do
    T.bind(self, CreateIssueOrchestration)
    return if issue.nil?

    T.must(issue).synchronize_search_index
  end

  step :update_close_issue_references do
    T.bind(self, CreateIssueOrchestration)
    return if issue.nil?

    T.must(issue).update_close_issue_references if should_update_close_issue_references
  end

  step :sync_pull_request_updated_at do
    T.bind(self, CreateIssueOrchestration)
    return if issue.nil?

    T.must(issue).sync_pull_request_updated_at
  end

  step :attach_matching_assets do
    T.bind(self, CreateIssueOrchestration)
    return unless issue = self.issue

    has_body = issue.body.present?
    issue.attach_matching_assets if has_body
  end
end
