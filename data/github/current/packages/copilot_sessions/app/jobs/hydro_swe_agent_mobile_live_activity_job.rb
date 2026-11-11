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
    @user_id = message[:initiating_user_id]
    @pull_request_id = message[:pull_request_id]
    @session_id = message[:session_id]
    @message = message
  end

  sig { void }
  def perform
    return unless @session_id.present? && @message.present? && SUPPORTED_HYDRO_TOPICS.include?(topic)
    return unless user && FeatureFlag.vexi.enabled?(:copilot_swe_agent_mobile_live_activity, user, default: false)
    return unless repository && owner
    return unless deliver_notification?
    return if excluded_agent?

    notification_layout = CopilotSessions::LiveActivityLayoutBuilder.build_layout(
      user: T.must(user),
      repository: repository,
      pull_request: pull_request,
      topic: topic,
      message: @message,
      timestamp: timestamp
    )
    return unless notification_layout

    publish_to_notifyd(notification_layout)
  end

  private

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

    result = GitHub::Aqueduct::Job.enqueue_hydro_message_job(
      payload.bytes,
      queue: Notifyd::Aqueduct::QUEUE,
      headers: headers.to_h,
      client: aqueduct_client,
    )

    result = result.rescue do |err|
      if err.is_a?(::GitHub::Aqueduct::Job::UnavailableError)
        GitHub.logger.error("Notifyd unavailable", error: err.message)
        GitHub::Result.error(Notifyd::Aqueduct::UnavailableError.new)
      else
        GitHub.logger.error("Unknown error publishing to notifyd", error: err.message)
        GitHub::Result.error(err)
      end
    end

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
    @topic == CopilotSessions::LiveActivityLayoutConfig::SESSION_QUEUE_HYDRO_TOPIC && @pull_request.nil?
  end

  sig { returns(T::Boolean) }
  def deliver_notification?
    return true unless @topic == CopilotSessions::LiveActivityLayoutConfig::SESSION_QUEUE_HYDRO_TOPIC

    FeatureFlag.vexi.enabled?(:copilot_swe_agent_enable_queued_notifications, user, default: false)
  end

  sig { returns(T::Boolean) }
  def excluded_agent?
    agent_id = @message[:agent_id]
    return false unless agent_id

    EXCLUDED_AGENT_IDS.include?(agent_id)
  end

  sig { returns(T::Array[Google::Protobuf::Any]) }
  def authzd_attributes
    if queued?
      # Use repository attributes when pull request is not available
      T.must(repository).permissions_wrapper.serialized_subject_attributes
    else
      T.must(pull_request).permissions_wrapper.serialized_subject_attributes
    end.map { |a| pack_into_pb_any(a) }
  end

  sig { returns(T::Hash[Symbol, String]) }
  def subject
    if queued?
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
    return {} if queued?

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
    return [{ type: "repository", value: repository&.id.to_s }] if queued?

    [
      { type: "repository", value: repository&.id.to_s },
      { type: "pull_request", value: pull_request&.id.to_s },
      { type: "issue", value: issue&.id.to_s },
    ]
  end

  # Memoize commonly used objects
  sig { returns(T.nilable(Issue)) }
  memoize def issue
    Issue.includes(:pull_request).find_by(pull_request_id: @pull_request_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  sig { returns(T.nilable(PullRequest)) }
  memoize def pull_request
    issue&.pull_request
  end

  sig { returns(T.nilable(Repository)) }
  memoize def repository
    if queued?
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
    if queued?
      repository&.owner
    else
      pull_request&.owner
    end
  end
end
