# typed: true
# frozen_string_literal: true

class Api::RepositoryDependabotAlerts < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::DependabotAlertsHelpers

  FORBIDDEN_MESSAGE = "You are not authorized to perform this operation."
  API_STATUS_MAP = T.let({
    agent_not_found: 404,
    agent_not_assignable: 422,
    agent_not_enabled: 403,
    target_repo_not_found: 404,
    target_repo_archived: 422,
    copilot_forbidden: 403,
    copilot_timeout: 504,
    copilot_unexpected: 500,
  }.freeze, T::Hash[Symbol, Integer])

  # Get a specific Dependabot alert by number
  get "/repositories/:repository_id/dependabot/alerts/:alert_number", operation_id: "dependabot/get-alert" do
    repo = find_repo!
    ensure_repo_access_and_dependabot_alerts_enabled!(repo)

    control_access :read_vulnerability_alerts,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    alert = find_alert!(repo)

    deliver(:dependabot_alert_hash, alert, last_modified: calc_last_modified_for_object(alert))
  end

  # This endpoint deals with dismissing, reopening, or updating assignees for an alert
  # via RepositoryVulnerabilityAlert#dismiss, #reopen, or #update_assignees.
  # Neither dismiss nor reopen can be performed on a fixed alert.
  patch "/repositories/:repository_id/dependabot/alerts/:alert_number", operation_id: "dependabot/update-alert" do
    repo = find_repo!
    ensure_repo_access_and_dependabot_alerts_enabled!(repo)

    control_access :write_vulnerability_alerts,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    alert = find_alert!(repo)
    data = receive_with_openapi
    valid_assignees = get_assignees!(data)

    if data.has_key?("state")
      if alert.state == "fixed"
        deliver_error!(409, message: "Fixed alerts cannot be dismissed or reopened")
      end

      if data["state"] == "dismissed"
        dismiss_alert(alert, data)
      else
        reopen_alert(alert, data)
      end
    end

    # Truthy when valid_assignees is an empty array (clear) or has items; nil when assignees key is absent.
    if valid_assignees
      begin
        alert.update_assignees(valid_assignees, current_user)
      rescue ActiveRecord::RecordInvalid => e
        deliver_error!(422, message: e.record.errors.full_messages.join(", "))
      end

      # Trigger Copilot agent job if an agent bot (copilot) was assigned and the feature is enabled
      copilot_swe_bot_assigned = valid_assignees.any? { |u| u.is_a?(Bot) && u.copilot_swe_agent? }
      if copilot_swe_bot_assigned && dependabot_copilot_assignment_rest_api_support_enabled?
        process_dependabot_agent_assignment!(alert, repo, data)
      end
    end

    deliver(:dependabot_alert_hash, alert)
  end

  get "/repositories/:repository_id/dependabot/alerts", operation_id: "dependabot/list-alerts-for-repo" do
    repo = find_repo!
    ensure_repo_access_and_dependabot_alerts_enabled!(repo)

    control_access :read_vulnerability_alerts,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    ensure_non_conflicting_cursor_params!

    alerts = alerts_for_repository(repository: repo)

    deliver(:dependabot_alerts_hash, { alerts: alerts }, last_modified: calc_last_modified(alerts))
  rescue Platform::Errors::Cursor,
    Search::Queries::CursorPagination::ParameterError,
    Platform::Errors::DuplicateFirstLastPaginationBoundaries,
    Platform::Errors::ExcessivePagination,
    Platform::Errors::InvalidPagination => e

    deliver_error!(400, message: e.message)
  end

  private

  # Checks if the Dependabot Copilot assignment REST API feature is enabled for the current user.
  def dependabot_copilot_assignment_rest_api_support_enabled?
    return false if current_user.nil?

    FeatureFlag.vexi.enabled?(:dependabot_alerts_assign_to_copilot, current_user, default: false) &&
    FeatureFlag.vexi.enabled?(:dependabot_copilot_assignment_rest_api_support, current_user, default: false)
  end

  sig do
    params(
      data: T::Hash[String, T::Array[String]],
    ).returns(T.nilable(T::Array[T.untyped]))
  end
  def get_assignees!(data)
    return nil unless data.has_key?("assignees")

    assignee_logins = T.must(data["assignees"]).compact_blank.map(&:downcase).uniq
    return [] unless assignee_logins.any?

    valid_assignees = lookup_assignees_by_login(assignee_logins)
    all_assignees_found = valid_assignees.size == assignee_logins.size
    unless all_assignees_found
      found_logins = valid_assignees.map { |u| u.is_a?(Bot) ? "#{u.slug}#{Bot::LOGIN_SUFFIX}".downcase : u.display_login.downcase }
      missing = assignee_logins - found_logins
      deliver_error!(422, message: "#{missing.join(", ")} could not be found")
    end

    # Keep real people and the copilot swe agent
    # For now, we strip any bot that's not Copilot (i.e. AgenticApp.agent_for_bot_id(u.id) not allowed)
    valid_assignees.select do |u|
      next true unless u.is_a?(Bot)

      dependabot_copilot_assignment_rest_api_support_enabled?  # allow bots if the feature flag is enabled
    end
  end

  # Looks up assignees (users and bots) by their login.
  # Bot logins end with "[bot]" suffix and are resolved via Bot.with_slugs.
  def lookup_assignees_by_login(logins)
    string_logins = Array(logins).grep(String)
    bot_logins, user_logins = string_logins.partition { |login| login.ends_with?(Bot::LOGIN_SUFFIX) }

    regular_users = user_logins.any? ? Users.domain.by_logins(user_logins) : []
    bots = bot_logins.any? ? Bot.with_slugs(bot_logins).to_a : []

    regular_users + bots
  end

  # Processes agent assignment for a Dependabot alert using the shared service.
  # For now, we keep parity with Issues and _only_ support copilot-swe-agent
  def process_dependabot_agent_assignment!(alert, repo, data)
    return unless Dependabot.dependabot_alert_assign_to_copilot_for?(repo, current_user)

    service = Dependabot::AgentAssignmentService.new
    agent_assignment = data["agent_assignment"] || {}
    agent_id = nil # Only support copilot-swe-agent
    agent, _bot, _app = service.resolve_agent!(agent_id: agent_id, repo: repo, user: current_user)

    # For now, we don't take in a target repo like Issues or the UI
    target_repo = repo

    service.validate_target_repo!(target_repo: target_repo, source_repo: repo, agent: agent, user: current_user)

    assignment_attributes = service.build_assignment_attributes(
      target_repo: target_repo,
      agent_id: agent.bot_id,
      user: current_user,
      base_branch: nil, # For now, we only support the default branch
      custom_instructions: agent_assignment["custom_instructions"],
      custom_agent: agent_assignment["custom_agent"],
      model: agent_assignment["model"],
      remote_ip: remote_ip,
      skip_pull_request: false, # For now, we only support creating a PR
    )

    token = resolve_dependabot_copilot_token

    service.execute_assignment!(
      alert: alert,
      user: current_user,
      token: token,
      attributes: assignment_attributes,
      failbot_context: "repository_dependabot_alerts_api",
    )
  rescue Dependabot::AgentAssignmentService::Error => e
    deliver_error!(API_STATUS_MAP.fetch(e.error_kind), message: e.message)
  end

  # Resolves a Copilot API token appropriate for the API context.
  # Follows the pattern from Issues API (process_copilot_agent_assignment).
  def resolve_dependabot_copilot_token
    request_token_value = request_credentials.token&.to_s
    viewer_using_pat = current_user.using_personal_access_token? || current_user.using_auth_via_user_programmatic_access?
    should_mint = viewer_using_pat && FeatureFlag.vexi.enabled?(:copilot_mint_token_for_api_requests, current_user, default: false)

    if request_token_value.present? && !should_mint
      GitHub.encrypt_and_encode_capi_token(request_token_value)
    elsif request_token_value.present?
      begin
        CopilotSessions::CopilotApiToken.get_encrypted(
          user: current_user,
          entry_point: :dependabot_alerts_api_copilot_assignment,
          user_session: nil,
          force_cache_miss: true,
        )
      rescue CopilotSessions::CopilotApiToken::IntegrationUnavailableError
        nil
      end
    end
  end
end
