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

    agent_specific = build_agent_specific_copilot_contexts(
      issue: issue,
      actor: actor_user,
      base_context: base_context_hash
    )

    if agent_specific.empty?
      if FeatureFlag.vexi.enabled?(:issues_copilot_skip_fallback_context, issue.repository, default: false)
        GitHub.logger.info({
          body: "[Copilot-Assign] Skipping fallback to base context — no assignable agent matched",
          issue_id: issue.id,
          repository_id: issue.repository_id,
          actor_id: actor_user.id,
          orchestration_type: "CreateIssueOrchestration",
        })
        GitHub.dogstats.increment("issues.copilot.skip_fallback_context",
          tags: ["orchestration_type:CreateIssueOrchestration"])
        return
      else
        # Legacy fallback: trigger with base context when no agent-specific contexts exist
        contexts_to_trigger = [base_context_hash]
      end
    else
      contexts_to_trigger = agent_specific
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

  step :trigger_triage_agent do
    T.bind(self, CreateIssueOrchestration)
    return unless issue = self.issue

    # Triage agent only applies to issues, not pull requests
    return if issue.pull_request?

    repository = issue.repository
    return unless repository

    # Check the repository is enrolled in the triage agent feature
    return unless IssuesTriageAgentFeature.enrolled?(repository)

    # Check if triage agent is enabled for this repository (admin can disable it)
    return unless repository.issue_triage_enabled?

    # When new config is enabled, read the config file and parse triggers
    if IssuesTriageAgentFeature.new_config_enabled?(repository)
      config_content = TriageAgent::Configuration.read_triage_agent_configuration(repository)
      unless config_content.present?
        emit_triage_agent_telemetry(issue, repository, "skipped_no_config", reason: "no configuration file found")
        return
      end

      # Skip triage if the config file has invalid frontmatter
      unless TriageAgent::Frontmatter::ConfigValidator.valid?(config_content)
        emit_triage_agent_telemetry(issue, repository, "skipped_invalid_config", reason: "configuration file has invalid frontmatter")
        return
      end

      # Parse triggers from the config and check if issue-create is enabled
      trigger_config = TriageAgent::Frontmatter::TriggerParser.parse(config_content)
      unless trigger_config.issue_create_enabled
        emit_triage_agent_telemetry(issue, repository, "skipped_trigger_disabled", reason: "issue-create trigger not enabled")
        return
      end

      # If issue-create has a filter, evaluate it — only triage matching issues
      if trigger_config.issue_create_has_filter?
        filter_query = T.must(trigger_config.issue_create_filter)
        result = TriageAgent::FilterEvaluator.evaluate(filter_query, issue)

        # Log any filter evaluation errors (fail-open: evaluator returns
        # matched=true for recoverable errors so the issue is still triaged)
        if result.error
          emit_triage_agent_telemetry(issue, repository, "filter_evaluation_warning", reason: "filter query returned error", error: result.error)
        end

        # Inclusion filter: skip triage for issues that don't match
        unless result.matched
          emit_triage_agent_telemetry(issue, repository, "skipped_filter_no_match", reason: "issue did not match inclusion filter")
          return
        end
      end
    end

    emit_triage_agent_telemetry(issue, repository, "issue_opened")

    Issues.domain.triage.trigger_triage_agent_job_twirp(issue: issue, repository: repository, type: :triage)
  end

  private

  sig { returns(CopilotContext) }
  def copilot_context
    IssueOrchestration.send(:deserialize_copilot_context, data[:copilot_context])
  end

  sig { params(issue: Issue, repository: Repository, event: String, reason: T.nilable(String), error: T.nilable(String)).void }
  def emit_triage_agent_telemetry(issue, repository, event, reason: nil, error: nil)
    metric_name = "triage_agent.#{event}"

    # Emit DataDog metric
    GitHub.dogstats.increment(metric_name)

    # Build log payload
    log_payload = {
      "code.namespace" => "CreateIssueOrchestration",
      "repository_id" => repository.id,
      "repository_nwo" => repository.name_with_display_owner,
      "issue_id" => issue.id,
      "issue_number" => issue.number,
    }
    log_payload["reason"] = reason if reason
    log_payload["error"] = error if error

    # Emit Splunk log (use warn level for skipped/error events)
    if event.start_with?("skipped")
      GitHub.logger.warn(metric_name, log_payload)
    else
      GitHub.logger.info(metric_name, log_payload)
    end

    # Emit Hydro/Kusto log only for successful triggers
    return if event.start_with?("skipped")

    GlobalInstrumenter.instrument("analytics.event", {
      actor: issue.user,
      category: "issue_triage_agent",
      action: "triage_issue",
      label: "repository_nwo:#{repository.name_with_display_owner} issue_id:#{issue.id}"
    })
  end
end
