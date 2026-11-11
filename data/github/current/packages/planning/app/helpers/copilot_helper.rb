# typed: true
# frozen_string_literal: true

module CopilotHelper
  class TokenMintingTimeout < Timeout::Error; end

  sig { params(user: User).returns(T::Boolean) }
  def user_has_projects_copilot_access?(user)
    Copilot::Public::User.for(user).has_copilot_access?
  end

  sig { params(project: MemexProject, user: T.nilable(User)).returns(T::Boolean) }
  def projects_copilot_tasks_enabled_for?(project:, user:)
    return false if GitHub.enterprise?
    return false unless user

    user_has_projects_copilot_access?(user)
  end

  sig { params(user: User).returns(T.nilable(Copilot::EncryptedToken)) }
  def build_copilot_api_token(user)
    actor_session = GitHub.context[:actor_session]
    user_session = UserSession.find_by(id: actor_session)

    Timeout.timeout(TOKEN_MINTING_TIMEOUT_S, TokenMintingTimeout) do
      CopilotSessions::CopilotApiToken.get_encrypted(
        user:,
        entry_point: :projects,
        user_session:
      )
    end
  rescue CopilotSessions::CopilotApiToken::IntegrationUnavailableError
    nil
  rescue TokenMintingTimeout
    org_bucket = org_count_bucket_tag(user)
    GitHub.dogstats.increment(
      "memex.build_copilot_api_token.error",
      tags: ["error:TokenMintingTimeout", org_bucket]
    )
    GitHub.logger.error(
      "memex build_copilot_api_token timed out",
      {
        "code.function": "build_copilot_api_token",
        "gh.user.id": user.id,
        "gh.request_id": GitHub.context[:request_id],
        "memex.token_minting_timeout_s": TOKEN_MINTING_TIMEOUT_S,
        "memex.org_count_bucket": org_bucket,
      }
    )
    nil
  rescue => e
    org_bucket = org_count_bucket_tag(user)
    GitHub.dogstats.increment(
      "memex.build_copilot_api_token.error",
      tags: ["error:#{e.class.name}", org_bucket]
    )
    GitHub.logger.error(
      "memex build_copilot_api_token failed",
      e,
      {
        "code.function": "build_copilot_api_token",
        "gh.user.id": user.id,
        "gh.request_id": GitHub.context[:request_id],
        "memex.org_count_bucket": org_bucket,
      }
    )
    nil
  end

  # Maximum time (seconds) allowed for minting a Copilot API token (DB writes:
  # grant, SAML credential authorizations, redeem). Must stay well under the 10s
  # TimeoutMiddleware budget to leave room for fetch_tasks + rendering.
  # P95 latency is ~1.2s, P99 is ~5-5.5s. A 2s timeout catches the long tail
  # while letting the vast majority through.
  TOKEN_MINTING_TIMEOUT_S = 2.0

  TASK_IDS_BATCH_SIZE = 100

  # Default timeout for individual Mission Control API calls (seconds).
  MISSION_CONTROL_DEFAULT_TIMEOUT_S = 1.0
  # Aggressive per-request timeout when :memex_mission_control_aggressive_timeout is enabled.
  MISSION_CONTROL_AGGRESSIVE_TIMEOUT_S = 0.3

  # Cumulative deadline for all Mission Control API calls within a single fetch_tasks invocation.
  MISSION_CONTROL_DEFAULT_DEADLINE_S = 3.0
  MISSION_CONTROL_AGGRESSIVE_DEADLINE_S = 1.0

  sig { params(user: User, task_ids: T::Array[String]).returns(T.nilable(T::Array[CopilotSessions::TaskApi::Task])) }
  def fetch_tasks(user:, task_ids:)
    if FeatureFlag.vexi.enabled?(:memex_disable_mission_control, default: false)
      GitHub.dogstats.increment("memex.fetch_agent_task_states.kill_switch")
      return nil
    end

    return nil unless user_has_projects_copilot_access?(user)

    token = build_copilot_api_token(user)
    return nil unless token

    timeout = mission_control_timeout_s
    deadline = mission_control_deadline_s
    started_at = GitHub::Dogstats.monotonic_time
    batches_fetched = T.let(0, Integer)

    all_tasks = T.let([], T::Array[CopilotSessions::TaskApi::Task])

    # Avoid sending an excessively long query string by batching task_ids
    task_ids.each_slice(TASK_IDS_BATCH_SIZE) do |task_ids_slice|
      elapsed = GitHub::Dogstats.monotonic_time - started_at
      if elapsed >= deadline
        GitHub.dogstats.increment("memex.fetch_agent_task_states.deadline_exceeded")
        break
      end

      batches_fetched += 1
      task_list = CopilotSessions::TaskApi::TaskList.batch_by_task_ids(
        user:,
        token:,
        task_ids: task_ids_slice,
        entry_point: :agent_tasks_for_projects,
        request_timeout_s: timeout
      )
      all_tasks.concat(task_list.tasks)
    end

    all_tasks
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    GitHub.dogstats.increment(
      "memex.fetch_agent_task_states.timeout",
      tags: ["error:#{e.class.name}"]
    )
    nil
  rescue CopilotAPI::RequestError => e
    GitHub.dogstats.increment(
      "memex.fetch_agent_task_states.error",
      tags: ["error:#{e.class.name}"]
    )
    GitHub.logger.error(
      {
        "code.function": "fetch_tasks",
        "exception.class": e.class.name,
        "exception.message": e.message,
        "memex.task_ids_count": task_ids.size,
        "memex.task_batches_attempted": batches_fetched,
        "memex.request_timeout_s": timeout,
        "memex.request_deadline_s": deadline,
      }
    )
    nil
  rescue => e
    GitHub.dogstats.increment(
      "memex.fetch_agent_task_states.error",
      tags: ["error:#{e.class.name}"]
    )
    nil
  ensure
    if started_at
      duration_ms = (GitHub::Dogstats.monotonic_time - started_at) * 1000
      GitHub.dogstats.distribution(
        "memex.fetch_agent_task_states.duration_ms",
        duration_ms,
        tags: ["batch_count:#{batches_fetched}"]
      )
    end
  end

  private

  sig { returns(Float) }
  def mission_control_timeout_s
    if FeatureFlag.vexi.enabled?(:memex_mission_control_aggressive_timeout, default: false)
      MISSION_CONTROL_AGGRESSIVE_TIMEOUT_S
    else
      MISSION_CONTROL_DEFAULT_TIMEOUT_S
    end
  end

  sig { returns(Float) }
  def mission_control_deadline_s
    if FeatureFlag.vexi.enabled?(:memex_mission_control_aggressive_timeout, default: false)
      MISSION_CONTROL_AGGRESSIVE_DEADLINE_S
    else
      MISSION_CONTROL_DEFAULT_DEADLINE_S
    end
  end

  sig { params(user: User).returns(String) }
  def org_count_bucket_tag(user)
    count = user.organizations.count
    bucket = case count
    when 0..5 then "0-5"
    when 6..20 then "6-20"
    when 21..50 then "21-50"
    when 51..100 then "51-100"
    else "100+"
    end
    "org_count_bucket:#{bucket}"
  rescue StandardError
    "org_count_bucket:unknown"
  end
end
