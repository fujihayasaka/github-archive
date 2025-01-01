# typed: true
# frozen_string_literal: true

class CreateIssueOrchestration < IssueOrchestration
  def only_save_on_orchestration_end? = true

  persist_feature_flags(
    :issues__orchestrate_reconcile_checklist,
    :issues__orchestrate_create_initial_events,
  )

  job_start

  step :instrument do
    T.bind(self, CreateIssueOrchestration)
    return unless issue = self.issue

    issue.instrument_creation_event(body_template_name: data[:body_template_name], is_duplicated: is_duplicated?)
  end

  step :clear_contributions_cache do
    T.bind(self, CreateIssueOrchestration)
    return unless issue = self.issue

    issue.clear_contributions_cache(context: "create_issue_orchestration")
  end

  step :synchronize_search_index do
    T.bind(self, CreateIssueOrchestration)
    return unless issue = self.issue

    issue.synchronize_search_index
  end

  step :update_close_issue_references do
    T.bind(self, CreateIssueOrchestration)
    return unless issue = self.issue

    issue.update_close_issue_references if should_update_close_issue_references
  end

  step :sync_pull_request_updated_at do
    T.bind(self, CreateIssueOrchestration)
    return unless issue = self.issue

    issue.sync_pull_request_updated_at
  end

  step :attach_matching_assets do
    T.bind(self, CreateIssueOrchestration)
    return unless issue = self.issue

    has_body = issue.body.present?
    issue.attach_matching_assets if has_body
  end

  step :subscribe_and_notify do
    T.bind(self, CreateIssueOrchestration)
    return unless issue = self.issue
    return if importing?

    issue.subscribe_and_notify
  end

  step :set_first_contribution_flag do
    T.bind(self, CreateIssueOrchestration)
    return unless issue = self.issue

    issue.set_first_contribution_flag
  end

  step :create_initial_events do
    T.bind(self, CreateIssueOrchestration)
    # The transient attribute issue.modifying_integration is used during milestone creation.
    return unless issue = self.issue_with_modifying_integration

    return unless feature_enabled?(:issues__orchestrate_create_initial_events)

    issue.create_initial_events
  end

  step :reconcile_checklist do
    T.bind(self, CreateIssueOrchestration)
    return unless feature_enabled?(:issues__orchestrate_reconcile_checklist)

    return unless reconcile_checklist?
    return unless issue = self.issue

    issue.reconcile_checklist
  end
end
