# typed: true
# frozen_string_literal: true

class CreateIssueCommentOrchestration < IssueCommentOrchestration
  def only_save_on_orchestration_end? = true
  def touch_issue_interval = 1

  job_start

  step :instrument_create_issue_comment do
    T.bind(self, CreateIssueCommentOrchestration)
    return if issue.nil? || issue_comment.nil? || issue_transfer?

    ActiveRecord::Base.connected_to(role: :reading) { T.must(issue_comment).instrument_creation }
  end

  step :attach_matching_assets do
    T.bind(self, CreateIssueCommentOrchestration)
    return if issue.nil? || issue_comment.nil? || issue_transfer?

    T.must(issue_comment).attach_matching_assets
  end

  step :subscribe_and_notify do
    T.bind(self, CreateIssueCommentOrchestration)
    return unless issue = self.issue
    return unless issue_comment = self.issue_comment
    return if issue_transfer?

    issue.subscribe(actor, :comment)
    issue_comment.subscribe_and_notify unless importing?
  end

  step :touch_issue do
    T.bind(self, CreateIssueCommentOrchestration)
    return unless issue = self.issue
    return unless issue_comment = self.issue_comment
    return if issue_transfer? || skip_touch_issue?

    TouchIssueJob.enqueue_once_per_interval(
      args: [issue.id, issue_comment.updated_at],
      interval: touch_issue_interval,
      unique_id: issue.id
    )
  end

  step :trigger_triage_agent_retriage do
    return unless issue = self.issue
    return unless issue_comment = self.issue_comment
    return if issue_transfer?

    # Triage agent only applies to issues, not pull requests
    return if issue.pull_request?

    repository = issue.repository
    return unless repository

    # Check repository enrollment and enablement
    return unless IssuesTriageAgentFeature.enrolled?(repository)
    return unless repository.issue_triage_enabled?

    # When new config is enabled, skip retriage if config file is missing
    if IssuesTriageAgentFeature.new_config_enabled?(repository)
      status = Issues.domain.triage.config_status(repository)

      unless status[:exists]
        GitHub.dogstats.increment("triage_agent.skipped_no_config")
        GitHub.logger.warn("triage_agent.skipped_no_config", {
          "code.namespace" => "CreateIssueCommentOrchestration",
          "repository_id" => repository.id,
          "repository_nwo" => repository.name_with_display_owner,
          "issue_id" => issue.id,
          "issue_number" => issue.number,
          "reason" => "config file missing",
        })
        return
      end

      # Skip retriage if the config file has invalid frontmatter
      if status[:valid] == false
        GitHub.dogstats.increment("triage_agent.skipped_invalid_config")
        GitHub.logger.warn("triage_agent.skipped_invalid_config", {
          "code.namespace" => "CreateIssueCommentOrchestration",
          "repository_id" => repository.id,
          "repository_nwo" => repository.name_with_display_owner,
          "issue_id" => issue.id,
          "issue_number" => issue.number,
          "reason" => "configuration file has invalid frontmatter",
        })
        return
      end

      raw_config = TriageAgent::Configuration.read_triage_agent_configuration(repository)
      trigger_config = TriageAgent::Frontmatter::TriggerParser.parse(raw_config)

      unless trigger_config.issue_comment_enabled
        GitHub.dogstats.increment("triage_agent.skipped_retriage_disabled")
        GitHub.logger.warn("triage_agent.skipped_retriage_disabled", {
          "code.namespace" => "CreateIssueCommentOrchestration",
          "repository_id" => repository.id,
          "repository_nwo" => repository.name_with_display_owner,
          "issue_id" => issue.id,
          "issue_number" => issue.number,
          "reason" => "issue-comment trigger disabled in config",
        })
        return
      end
    end

    # Make sure that a user and not the Copilot bot is triggering the retriage
    # This is to prevent infinite loops of the triage agent commenting and triggering itself
    return if CopilotSweAgent::Helpers.is_user_swe_agent?(actor)

    # Check if the actor has triage+ role to invoke retriage
    return unless Issues.domain.triage.can_invoke_retriage?(actor, repository, issue: issue)

    # Check if the comment contains a @copilot mention
    return unless comment_mentions_copilot?

    emit_triage_agent_retriage_telemetry(issue, repository, issue_comment)

    Issues.domain.triage.trigger_triage_agent_job_twirp(issue: issue, repository: repository, type: :retriage, comment: issue_comment, actor: actor)
  end

  private

  sig { returns(T::Boolean) }
  def comment_mentions_copilot?
    return false unless issue_comment&.body

    # Simple case-insensitive check for @copilot mention
    # This covers @copilot, @Copilot, @COPILOT, etc.
    T.must(issue_comment).body.match?(/(?:^|[^a-zA-Z0-9_])@copilot(?:[^a-zA-Z0-9_]|$)/i)
  end

  sig { params(issue: Issue, repository: Repository, issue_comment: IssueComment).void }
  def emit_triage_agent_retriage_telemetry(issue, repository, issue_comment)
    # Emit DataDog metric
    GitHub.dogstats.increment("triage_agent.retriage_triggered")

    # Emit Splunk log
    GitHub.logger.info("triage_agent.retriage_triggered", {
      "code.namespace" => "CreateIssueCommentOrchestration",
      "repository_id" => repository.id,
      "repository_nwo" => repository.name_with_display_owner,
      "issue_id" => issue.id,
      "issue_number" => issue.number,
      "issue_comment_id" => issue_comment.id,
      "actor_id" => actor&.id
    })

    # Emit Hydro/Kusto log
    GlobalInstrumenter.instrument("analytics.event", {
      actor: actor,
      category: "issue_triage_agent",
      action: "retriage_issue",
      label: "repository_nwo:#{repository.name_with_display_owner} issue_id:#{issue.id} comment_id:#{issue_comment.id}"
    })
  end

  sig { returns(T::Boolean) }
  def issue_transfer?
    data[:issue_transfer].blank? ? false : data[:issue_transfer]
  end

  sig { returns(T::Boolean) }
  def issue_previous_changes_empty?
    data[:issue_previous_changes_empty].blank? ? false : data[:issue_previous_changes_empty]
  end
end
