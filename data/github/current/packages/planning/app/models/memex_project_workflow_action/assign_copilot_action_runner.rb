# typed: true
# frozen_string_literal: true

class MemexProjectWorkflowAction::AssignCopilotActionRunner < MemexProjectWorkflowAction::BaseActionRunner
  include GitHub::Memoizer

  ACTION_TYPE = :assign_copilot
  CONFIGURED_MODEL_UNAVAILABLE_METRIC = "memex.auto_assign_agent.configured_model_unavailable"

  sig { returns(T::Array[MemexProjectItem]) }
  def run
    log_duration do
      raise NotImplementedError, "Manual run not implemented for assign_copilot action" if @manual_run

      assign_copilot_to_items
    end
  end

  private

  sig { returns(MemexProject) }
  def memex_project
    @action.workflow.memex_project
  end

  # Extends the shared log_payload with auto-assign-agent-specific attribution so we
  # can answer "who configured this prompt vs. who triggered it" in telemetry,
  # which is required by the Secure AI Standard / Platform Health for the
  # M5 private preview. The literal `instruction` is intentionally not logged
  # (user-authored content); we log presence and length instead.
  def log_payload(project_item: nil, **extra)
    super(project_item: project_item, **extra).merge(
      workflow_id: @action.workflow.id,
      workflow_creator_id: @action.workflow.creator_id,
      instruction_present: @action.arguments["instruction"].present?,
      instruction_length: @action.arguments["instruction"].to_s.length
    )
  end

  # Use the first allowedRepositories entry if configured, otherwise fall back to the issue's repo
  sig { params(issue: Issue).returns(Repository) }
  def resolve_target_repository(issue)
    allowed_repos = @action.arguments["allowedRepositories"]
    if allowed_repos.is_a?(Array) && allowed_repos.first.present?
      repo = Repositories.domain.by_qualified_name(allowed_repos.first)
      return T.cast(repo, Repository) if repo # rubocop:disable GitHub/AvoidCast
    end
    T.must(issue.repository)
  end

  sig { returns(T::Array[MemexProjectItem]) }
  def assign_copilot_to_items
    unless MemexProjectFeatureCheck.enabled?(:memex_autopilot, memex_project, actor: @actor)
      log_action_skipped(**log_payload(project_item: @input.first, reason: "memex_autopilot_flag_disabled")) if @input.any?
      return []
    end

    items = []

    @input.each_slice(BATCH_SIZE) do |batch|
      MemexProject.throttle do
        batch.each do |project_item|
          assign_copilot_to_item(project_item, items)
        end
      end
    end

    items
  end

  sig { params(project_item: MemexProjectItem, items: T::Array[MemexProjectItem]).void }
  def assign_copilot_to_item(project_item, items)
    if project_item.content.nil? || project_item.content.is_a?(DraftIssue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      log_action_skipped(**log_payload(project_item: project_item, reason: REASON_DOES_NOT_HAVE_CONTENT))
      return
    end

    unless project_item.content.is_a?(Issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      log_action_skipped(**log_payload(project_item: project_item, reason: REASON_IS_NOT_AN_ISSUE))
      return
    end

    # Only trigger for human actors — bots (e.g. MemexAutomation) cannot mint CAPI tokens.
    # See ADR Decision 7: Human-Only Triggers.
    if @actor.nil? || @actor.bot?
      log_action_skipped(**log_payload(project_item: project_item, reason: "actor_not_human"))
      return
    end

    issue = T.cast(project_item.content, Issue)
    repository = resolve_target_repository(issue)

    # Verify Copilot SWE agent is enabled for this repository
    unless T.must(repository.owner).copilot_swe_agent_enabled_for?(repository)
      log_action_skipped(**log_payload(project_item: project_item, reason: "copilot_not_enabled"))
      return
    end

    # Dedup guard (github/planning-tracking#3129): if a prior auto-assign for this issue
    # and this workflow action is still in flight (a pending/active AgentAssignment),
    # skip instead of spawning a duplicate session. Rapid in/out moves of the item across
    # the Auto-Assign Status column would otherwise queue multiple sessions behind the
    # active one. Placed before try_acquire_concurrency_slot! so a known duplicate does not
    # consume a concurrency slot. Read on the writing role so we observe a just-created row
    # rather than a possibly-stale replica.
    already_in_flight = with_write do
      Issues.domain.copilot.in_flight_assignment_for_source?(
        issue: issue,
        source_type: :workflow_action,
        source_id: @action.id,
      )
    end

    if already_in_flight
      log_action_skipped(**log_payload(project_item: project_item, reason: "already_assigned"))
      return
    end

    # Acquire concurrency slot after all eligibility checks pass, so early
    # returns for ineligible items don't consume capacity.
    unless try_acquire_concurrency_slot!
      log_action_skipped(**log_payload(project_item: project_item, reason: "at_capacity"))
      return
    end

    attrs = Issues::AgentAssignmentNewAttributes.new(
      target_repository: repository,
      custom_instructions: @action.arguments["instruction"],
      skip_pull_request: @action.arguments["outputMode"] != "pull_request",
      model: configured_model,
      source_type: :workflow_action,
      source_id: @action.id,
    )

    token = CopilotSessions::CopilotApiToken.get_encrypted_for_background_actor(
      user: @actor,
      entry_point: :projects_autopilot,
    )

    result = with_write do
      Issues.domain.copilot.assign_copilot_to_issues(
        actor: @actor,
        issues: [issue],
        assignment_attributes: attrs,
        token: token,
        use_async: true
      )
    end

    if result[:successful_issues].blank?
      release_concurrency_slot!
      log_action_skipped(**log_payload(project_item: project_item, reason: "assign_copilot_failed"))
      return
    end

    items << project_item
  rescue CopilotAPI::UnauthorizedError, GitHub::Sweagentd::Client::Jobs::UnauthorizedError => e
    GitHub.logger.warn(
      "AssignCopilotActionRunner: auth error for issue #{project_item.content_id}, will not retry",
      "gh.issue.id" => project_item.content_id,
      "gh.actor.id" => @actor&.id,
      "gh.project.id" => memex_project.id,
      "gh.workflow.id" => @action.workflow.id,
      "gh.workflow.creator_id" => @action.workflow.creator_id,
      "error" => e.message
    )
    log_action_skipped(**log_payload(project_item: project_item, reason: "assign_copilot_auth_error"))
    release_concurrency_slot!
  rescue StandardError => e
    Failbot.report(e, app: "memex-autopilot", context: {
      project_item_id: project_item.id,
      actor_id: @actor&.id,
      project_id: memex_project.id,
      workflow_id: @action.workflow.id,
      workflow_creator_id: @action.workflow.creator_id
    })
    log_action_skipped(**log_payload(project_item: project_item, reason: "assign_copilot_error"))
    release_concurrency_slot!
  end

  sig { returns(T::Boolean) }
  def try_acquire_concurrency_slot!
    state = @action.agent_workflow_state
    return true unless state # No state row = no limit enforced (backwards compat)

    with_write { state.try_increment! }
  end

  sig { void }
  def release_concurrency_slot!
    state = @action.agent_workflow_state
    return unless state

    with_write { state.decrement! }
  rescue StandardError => e
    Failbot.report(e, app: "memex-autopilot", context: {
      method: "release_concurrency_slot!",
      action_id: @action.id,
      project_id: memex_project.id,
      workflow_id: @action.workflow.id
    })
  end

  sig { returns(T.nilable(String)) }
  def configured_model
    model = @action.arguments["model"].presence
    return unless model
    return model if available_model_keys.include?(model)

    GitHub.dogstats.increment(CONFIGURED_MODEL_UNAVAILABLE_METRIC, tags: ["owner_type:#{memex_project.owner_type}"])
    nil
  end

  sig { returns(T::Array[String]) }
  memoize def available_model_keys
    copilot_entity = case owner = memex_project.owner
    when User
      Copilot::User.new(owner)
    when Organization
      Copilot::Organization.new(owner)
    end

    return [] unless copilot_entity
    Copilot::ModelsRegistryCache.for_entity(copilot_entity).filter_map(&:model_key)
  end
end
