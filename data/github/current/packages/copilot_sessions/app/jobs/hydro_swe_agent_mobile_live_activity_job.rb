# typed: true
# frozen_string_literal: true

class HydroSweAgentMobileLiveActivityJob < HydroMessageJob
  queue_as :hydro_swe_agent_mobile_live_activity
  retry_on_dirty_exit

  include GitHub::Memoizer

  SUPPORTED_HYDRO_TOPICS = [
    CopilotSessions::LiveActivityLayoutConfig::SESSION_QUEUE_HYDRO_TOPIC,
    CopilotSessions::LiveActivityLayoutConfig::SESSION_START_HYDRO_TOPIC,
    CopilotSessions::LiveActivityLayoutConfig::SESSION_FINISH_HYDRO_TOPIC
  ]

  SUPPORTED_HYDRO_TOPICS_V2 = [
    CopilotSessions::LiveActivityLayoutConfig::DECOUPLED_QUEUE_HYDRO_TOPIC,
    CopilotSessions::LiveActivityLayoutConfig::DECOUPLED_START_HYDRO_TOPIC,
    CopilotSessions::LiveActivityLayoutConfig::DECOUPLED_FINISH_HYDRO_TOPIC,
  ]

  LOCK_CONCURRENT_JOBS = 1
  LOCK_TTL = 1.minute

  # Agent IDs for Copilot Code Review agents across different environments
  # Based on https://github.com/github/github-ui/blob/c99b88a10a2480c46054e67d59967374112258fb/packages/agent-sessions/types/session.ts#L135-L141
  #
  # TODO: Switch to filtering by integration ID once that's available in the sessions API
  # https://github.com/github/agent-session-experience/issues/278
  CODE_REVIEW_AGENT_IDS = [946600, 71, 106, 776, 386, 56]

  # Agent IDs to exclude from live activity notifications
  EXCLUDED_AGENT_IDS = [CODE_REVIEW_AGENT_IDS].flatten

  def initialize(protobuf:, headers:, schema:, timestamp:, timestamp_nano:, message:, queue:)
    super
    @v2 = T.let(false, T::Boolean)
    @user_id = message[:initiating_user_id]
    @pull_request_id = message[:pull_request_id]
    @session_id = message[:session_id]
    @message = message
  end

  sig { void }
  def perform
    # V2 decoupled topics — completely isolated path, gated by feature flag.
    # Falls through to existing v1 code if topic is not a v2 topic.
    if SUPPORTED_HYDRO_TOPICS_V2.include?(topic)
      return perform_v2
    end

    return unless SUPPORTED_HYDRO_TOPICS.include?(topic)
    return unless is_valid?

    # Apply a job restraint lock to prevent multiple jobs from sending duplicate notifications for the same session.
    if obtained_lock?
      notification_layout = CopilotSessions::LiveActivityLayoutBuilder.build_layout(
        user: T.must(user),
        repository: repository,
        pull_request: pull_request,
        topic: topic,
        message: @message,
        timestamp: timestamp
      )

      unless notification_layout
        log_skipped("layout_nil")
        return
      end

      publish_to_notifyd(notification_layout)
    else
      # Instrument locking failures for visibility, but do not treat as an error since it just means another job is processing this message
      # Silently fail to prevent requeuing this job.
      GitHub.dogstats.increment("hydro_swe_agent_mobile_live_activity.skipped_duplicate", tags: telemetry_tags)

      if user && FeatureFlag.vexi.enabled?(:copilot_swe_agent_mobile_live_activity_lock_logging, user, default: false)
        GitHub.logger.info("hydro_swe_agent_mobile_live_activity.skipped_duplicate", telemetry_context)
      end
    end
  end

  private

  # obtained_lock? applies a job restraint lock to prevent multiple jobs from sending duplicate notifications for the same session.
  # GitHub::Restraint::Lock! is insufficient as it releases the lock as soon as the job completes and does not prevent duplicates after the first job run.
  # In order to prevent this, we use #obtain_lock, which will release the lock after a specified TTL, preventing duplicate notifications for 1 minute after the first job obtains the lock.
  # The cache key will automatically evict after the TTL expires, so it does not require any manual cleanup.
  sig { returns(T::Boolean) }
  def obtained_lock?
    # Disable this feature flag as a circuit breaker in case of any unforeseen issues with locking.
    if FeatureFlag.vexi.enabled?(:copilot_swe_agent_mobile_live_activity_lock, user, default: false)
      lock_key = "hydro_swe_agent_mobile_live_activity:#{@user_id}:#{topic}:#{@session_id}"
      restraint = GitHub::Restraint.new
      locked = !!restraint.obtain_lock(lock_key, LOCK_CONCURRENT_JOBS, LOCK_TTL)

      GitHub.logger.info("hydro_swe_agent_mobile_live_activity.lock_attempted", telemetry_context.merge(locked: locked))
      GitHub.dogstats.increment("hydro_swe_agent_mobile_live_activity.lock_attempted", tags: telemetry_tags + ["locked:#{locked}"])

      locked
    else
      GitHub.logger.info("hydro_swe_agent_mobile_live_activity.lock_skipped", telemetry_context.merge(reason: "feature_flag_disabled"))
      GitHub.dogstats.increment("hydro_swe_agent_mobile_live_activity.lock_skipped", tags: telemetry_tags + ["reason:feature_flag_disabled"])

      true
    end
  end

  sig { returns(T::Boolean) }
  def is_valid?
    unless @session_id.present? && @message.present?
      log_skipped("invalid_message")
      return false
    end

    GitHub.logger.info("hydro_swe_agent_mobile_live_activity.received", telemetry_context)
    GitHub.dogstats.increment("hydro_swe_agent_mobile_live_activity.received", tags: telemetry_tags)

    feature_flag = @v2 ? :copilot_swe_agent_mobile_live_activity_v2 : :copilot_swe_agent_mobile_live_activity
    unless user && FeatureFlag.vexi.enabled?(feature_flag, user, default: false)
      log_skipped(@v2 ? "v2_feature_flag_disabled" : "feature_flag_disabled")
      return false
    end

    # When v2 is enabled for this user, skip v1 to avoid duplicate notifications.
    # The v2 path (perform_v2) will handle the decoupled event instead.
    if !@v2 && FeatureFlag.vexi.enabled?(:copilot_swe_agent_mobile_live_activity_v2, user, default: false)
      log_skipped("v2_enabled_skipping_v1")
      return false
    end

    unless repository && owner
      log_skipped("missing_repo_or_owner")
      return false
    end

    unless deliver_notification?
      log_skipped("queued_not_enabled")
      return false
    end

    if excluded_agent?
      log_skipped("excluded_agent")
      return false
    end

    true
  end

  sig { params(notification_layout: T.nilable(Notifyd::Proto::Layouts::Mobile::LiveActivity)).returns(T.nilable(T::Boolean)) }
  def publish_to_notifyd(notification_layout)
    return unless notifyd_enabled?
    return unless notification_layout

    notification = build_notifyd_payload(notification_layout)

    headers = Notifyd::MessageHeaders.new.with_github_env.with_tenant_context.with_telemetry
    headers[:producer] = "github-notifyd"

    aqueduct_client = Notifyd::Aqueduct.default_client_for
    payload = Notifyd::Aqueduct::ProtobufPayload.new(notification)
    if payload.bytesize >= Notifyd::NotifyPublisher::PAYLOAD_SIZE_TO_COMPRESS
      payload = Notifyd::Aqueduct::DeflatedPayload.new(payload)
    end
    headers = Notifyd::Aqueduct.populate_headers(headers, payload: payload)

    result = T.let(nil, T.nilable(GitHub::Result))
    GitHub.dogstats.distribution_time("hydro_swe_agent_mobile_live_activity.publish_duration", tags: telemetry_tags) do
      result = GitHub::Aqueduct::Job.enqueue_hydro_message_job(
        payload.bytes,
        queue: Notifyd::Aqueduct::QUEUE,
        headers: headers.to_h,
        client: aqueduct_client,
      )
    end

    return unless result

    result = result.rescue do |err|
      GitHub.dogstats.increment("hydro_swe_agent_mobile_live_activity.publish_error", tags: telemetry_tags)
      if err.is_a?(::GitHub::Aqueduct::Job::UnavailableError)
        GitHub.logger.error("hydro_swe_agent_mobile_live_activity.publish_error", telemetry_context.merge(error: err.message, error_type: "unavailable"))
        GitHub::Result.error(Notifyd::Aqueduct::UnavailableError.new)
      else
        GitHub.logger.error("hydro_swe_agent_mobile_live_activity.publish_error", telemetry_context.merge(error: err.message, error_type: "unknown"))
        GitHub::Result.error(err)
      end
    end

    GitHub.logger.info("hydro_swe_agent_mobile_live_activity.published", telemetry_context)
    GitHub.dogstats.increment("hydro_swe_agent_mobile_live_activity.published", tags: telemetry_tags)

    result.value!
  end

  sig { params(notification_layout: Notifyd::Proto::Layouts::Mobile::LiveActivity).returns(Hash) }
  def build_notifyd_payload(notification_layout)
    {
      actor: {
        id: @user_id
      },
      context: {
        repository_id: T.must(repository).id,
        owner_id: T.must(owner).id,
        owner_type: T.must(owner).user? ? :USER : :ORGANIZATION,
        trigger: "unknown"
      },
      rendering: {
        mobile: notification_layout
      },
      authorization: {
        authzd_attributes:,
        saml_enforcement: T.must(owner).organization? ? { organization_id: T.must(owner).id } : { skip_enforcement: true }
      },
      tracking: {
        triggered_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i),
        subject_metadata:
      },
      notification_id: @session_id,
      subject:,
      related_topics:,
      explicit_recipients: [{ reason: "live_activity_copilot_coding_agent", user_ids: [@user_id] }],
      feature_swiches: Google::Protobuf::Map.new(:string, :bool).tap { |pb| pb["notify_actor"] = true }
    }
  end

  sig { returns(T::Boolean) }
  def queued?
    queue_topic = @v2 ? CopilotSessions::LiveActivityLayoutConfig::DECOUPLED_QUEUE_HYDRO_TOPIC : CopilotSessions::LiveActivityLayoutConfig::SESSION_QUEUE_HYDRO_TOPIC
    @topic == queue_topic && @pull_request.nil?
  end

  # Whether the resource (e.g. PR) is not yet available.
  # For v1: only true when queued. For v2: also true when no PR is available.
  sig { returns(T::Boolean) }
  def resource_pending?
    queued? || (@v2 && pull_request.nil?)
  end

  sig { returns(T::Boolean) }
  def deliver_notification?
    if @topic == CopilotSessions::LiveActivityLayoutConfig::SESSION_QUEUE_HYDRO_TOPIC
      return FeatureFlag.vexi.enabled?(:copilot_swe_agent_enable_queued_notifications, user, default: false)
    end

    if @topic == CopilotSessions::LiveActivityLayoutConfig::DECOUPLED_QUEUE_HYDRO_TOPIC
      return FeatureFlag.vexi.enabled?(:copilot_swe_agent_enable_queued_notifications_v2, user, default: false)
    end

    true
  end

  sig { returns(T::Boolean) }
  def excluded_agent?
    agent_id = @message[:agent_id]
    return false unless agent_id

    EXCLUDED_AGENT_IDS.include?(agent_id)
  end

  sig { returns(T::Array[Google::Protobuf::Any]) }
  def authzd_attributes
    if resource_pending?
      # Use repository attributes when pull request is not available
      T.must(repository).permissions_wrapper.serialized_subject_attributes
    else
      T.must(pull_request).permissions_wrapper.serialized_subject_attributes
    end.map { |a| pack_into_pb_any(a) }
  end

  sig { returns(T::Hash[Symbol, String]) }
  def subject
    if resource_pending?
      {
        type: repository.class.name,
        value: T.must(repository).id.to_s
      }
    else
      {
        type: pull_request.class.name,
        value: @pull_request_id.to_s
      }
    end
  end

  sig { returns(T::Boolean) }
  def notifyd_enabled?
    !GitHub.enterprise?
  end

  sig { params(data: T.untyped).returns(Google::Protobuf::Any) }
  def pack_into_pb_any(data)
    Google::Protobuf::Any.new.tap { |any| any.pack(data) }
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def subject_metadata
    return {} if resource_pending?

    subject = pull_request

    list = pull_request.try(:notifications_list)
    thread = pull_request.try(:notifications_thread)
    return {} unless list && thread

    {
      list_id: Newsies::List.to_id(list).to_s,
      list_type: Newsies::List.to_type(list),
      thread_id: Newsies::Thread.to_id(thread).to_s,
      thread_type: Newsies::Thread.to_type(thread),
      comment_id: Newsies::Comment.to_id(subject).to_s,
      comment_type: Newsies::Comment.to_type(subject)
    }
  end

  sig { returns(T::Array[T::Hash[Symbol, String]]) }
  def related_topics
    return [{ type: "repository", value: repository&.id.to_s }] if resource_pending?

    [
      { type: "repository", value: repository&.id.to_s },
      { type: "pull_request", value: pull_request&.id.to_s },
      { type: "issue", value: issue&.id.to_s },
    ]
  end

  # Telemetry helpers for structured logging and metrics
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def telemetry_context
    {
      session_id: @session_id,
      topic: topic,
      user_id: @user_id,
      pull_request_id: @pull_request_id,
      agent_id: @message&.dig(:agent_id),
      repository_id: @message&.dig(:repository_id),
      session_state: derived_session_state
    }
  end

  sig { returns(T::Array[String]) }
  def telemetry_tags
    tags = ["topic:#{topic}", "version:#{@v2 ? "v2" : "v1"}"]
    tags << "session_state:#{derived_session_state}" if derived_session_state
    tags
  end

  sig { params(reason: String).void }
  def log_skipped(reason)
    GitHub.logger.info("hydro_swe_agent_mobile_live_activity.skipped", telemetry_context.merge(reason: reason))
    GitHub.dogstats.increment("hydro_swe_agent_mobile_live_activity.skipped", tags: telemetry_tags + ["reason:#{reason}"])
  end

  sig { returns(T.nilable(String)) }
  memoize def derived_session_state
    state = CopilotSessions::SessionState.from_hydro_message(topic, @message || {})
    state&.serialize
  end

  # Memoize commonly used objects
  sig { returns(T.nilable(Issue)) }
  memoize def issue
    return unless @pull_request_id

    Issue.includes(:pull_request).find_by(pull_request_id: @pull_request_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  sig { returns(T.nilable(PullRequest)) }
  memoize def pull_request
    issue&.pull_request
  end

  sig { returns(T.nilable(Repository)) }
  memoize def repository
    if resource_pending?
      Repository.find_by(id: @message[:repository_id])
    else
      pull_request&.repository
    end
  end

  sig { returns(T.nilable(User)) }
  memoize def user
    User.find_by(id: @user_id)
  end

  sig { returns(T.nilable(T.any(Organization, User))) }
  memoize def owner
    if resource_pending?
      repository&.owner
    else
      pull_request&.owner
    end
  end

  # ============================================================================
  # V2 DECOUPLED EVENT HANDLING
  #
  # perform_v2 remaps decoupled message fields onto the v1 instance variables
  # (@user_id, @pull_request_id, @session_id), sets @v2 = true, then reuses the
  # entire v1 validation/lock/publish pipeline. Only queued?, deliver_notification?,
  # and is_valid? branch on @v2 — everything else works unchanged.
  # ============================================================================

  sig { void }
  def perform_v2
    @v2 = true
    @user_id = @message[:user_id]
    @pull_request_id = v2_derive_pull_request_id
    @session_id = @message[:session_id]

    # Silently discard when v2 flag is off — no telemetry to avoid noise
    # since every agent session event sends both v1 and v2 Hydro messages.
    return unless user && FeatureFlag.vexi.enabled?(:copilot_swe_agent_mobile_live_activity_v2, user, default: false)

    return unless is_valid?

    if obtained_lock?
      notification_layout = CopilotSessions::LiveActivityLayoutBuilder.build_layout(
        user: T.must(user),
        repository: repository,
        pull_request: pull_request,
        topic: topic,
        message: @message,
        timestamp: timestamp
      )

      unless notification_layout
        log_skipped("layout_nil")
        return
      end

      publish_to_notifyd(notification_layout)
    else
      GitHub.dogstats.increment("hydro_swe_agent_mobile_live_activity.skipped_duplicate", tags: telemetry_tags)

      if user && FeatureFlag.vexi.enabled?(:copilot_swe_agent_mobile_live_activity_lock_logging, user, default: false)
        GitHub.logger.info("hydro_swe_agent_mobile_live_activity.skipped_duplicate", telemetry_context)
      end
    end
  end

  # Derives pull_request_id from generic resource_type/resource_id fields.
  sig { returns(T.nilable(Integer)) }
  def v2_derive_pull_request_id
    resource_type = v2_unwrap_value(@message[:resource_type])
    normalized_resource_type = resource_type.to_s.downcase
    return unless normalized_resource_type == "pullrequest" || normalized_resource_type == "pull"

    v2_unwrap_value(@message[:resource_id])
  end

  # Unwraps protobuf wrapper types (google.protobuf.StringValue/Int64Value
  # arrive as Hashes with :value key after Hydro deserialization).
  sig { params(field: T.untyped).returns(T.untyped) }
  def v2_unwrap_value(field)
    field.is_a?(Hash) ? field[:value] : field
  end
end
