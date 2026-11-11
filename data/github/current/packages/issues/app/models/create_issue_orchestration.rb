# typed: true
# frozen_string_literal: true

class CreateIssueOrchestration < IssueOrchestration
  def only_save_on_orchestration_end? = true

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

    issue.create_initial_events
  end

  step :reconcile_checklist do
    T.bind(self, CreateIssueOrchestration)

    return unless reconcile_checklist?
    return unless issue = self.issue

    issue.reconcile_checklist
  end

  step :trigger_copilot_job do
    T.bind(self, CreateIssueOrchestration)
    return unless issue = self.issue
    return unless copilot_context
    return unless actor

    actor_user = T.must(actor)
    base_context = T.must(copilot_context)
    base_context_hash = T.cast(base_context, T::Hash[Symbol, T.untyped])

    repository = T.must(issue.repository)

    contexts_to_trigger = if repository.feature_flag_enabled?(:issues_create_3p_support, default: false)
      agent_specific = build_agent_specific_copilot_contexts(
        issue: issue,
        actor: actor_user,
        base_context: base_context_hash
      )
      # If there are no agent-specific contexts, fall back to the base context
      agent_specific.empty? ? [base_context_hash] : agent_specific
    else
      [base_context_hash]
    end

    contexts_to_trigger.each do |context|
      CopilotSweAgentJobHelper.trigger_job_with_error_handling(
        issue: issue,
        actor: actor_user,
        copilot_context: context,
        orchestration_type: "CreateIssueOrchestration"
      )
    end
  end

  private

  sig { returns(CopilotContext) }
  def copilot_context
    IssueOrchestration.send(:deserialize_copilot_context, data[:copilot_context])
  end
end
