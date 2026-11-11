# typed: true
# frozen_string_literal: true

class CopilotSessions::LiveActivityLayoutBuilder
  sig do
    params(
      user: User,
      repository: T.nilable(Repository),
      pull_request: T.nilable(PullRequest),
      topic: String,
      message: T::Hash[Symbol, T.untyped],
      timestamp: Integer
    ).returns(T.nilable(Notifyd::Proto::Layouts::Mobile::LiveActivity))
  end
  def self.build_layout(user:, repository:, pull_request:, topic:, message:, timestamp:)
    new(user: user, repository: repository, pull_request: pull_request, topic: topic, message: message, timestamp: timestamp).build_layout
  end

  def initialize(user:, repository:, pull_request:, topic:, message:, timestamp:)
    @user = user
    @repository = repository
    @pull_request = pull_request
    @topic = topic
    @session_id = message[:session_id]
    @message = message
    @timestamp = timestamp
    @session_state = CopilotSessions::SessionState.from_hydro_message(topic, @message)
    @config = CopilotSessions::LiveActivityLayoutConfig.config_for_state(@session_state)
  end

  sig { returns(T.nilable(Notifyd::Proto::Layouts::Mobile::LiveActivity)) }
  def build_layout
    return unless @config

    case @topic
    when CopilotSessions::LiveActivityLayoutConfig::SESSION_QUEUE_HYDRO_TOPIC
      return unless @repository
    else
      return unless @repository && @pull_request
    end

    build_notification_layout(@config)
  end

  private

  # Base layout builder for Agent Session live activity notifications
  sig { params(config: T::Hash[Symbol, T.untyped]).returns(Notifyd::Proto::Layouts::Mobile::LiveActivity) }
  def build_notification_layout(config)
    layout = {
      live_activity_session_id: @session_id,
      title: @pull_request&.title || "Copilot Agent Session",
      subtitle: config[:subtitle],
      event_timestamp: Google::Protobuf::Timestamp.new(seconds: @timestamp),
      event_type: config[:event_type],
      content_state: build_content_state(config[:content_state])
    }

    layout[:body] = config[:body] if config[:body]

    if config[:include_attributes]
      layout.merge!(
        attributes: build_attributes,
        attributes_type: "CodingAgentAttributes",
        url: T.must(@pull_request).url
      )
    end

    Notifyd::Proto::Layouts::Mobile::LiveActivity.new(**layout)
  end

  sig { params(content_config: T.nilable(T::Array[Symbol])).returns(Hash) }
  def build_content_state(content_config)
    if content_config.present?
      content_config.each_with_object({}) do |key, hash|
        value = if key == :session_state && @topic != CopilotSessions::LiveActivityLayoutConfig::SESSION_FINISH_HYDRO_TOPIC
          case @topic
          when CopilotSessions::LiveActivityLayoutConfig::SESSION_QUEUE_HYDRO_TOPIC
            "queued"
          when CopilotSessions::LiveActivityLayoutConfig::SESSION_START_HYDRO_TOPIC
            "in_progress"
          end
        else
          @message[key]
        end

        hash[key.to_s] = Google::Protobuf::Value.new(string_value: value.to_s) if value
      end
    else
      {}
    end
  end

  sig { returns(Hash) }
  def build_attributes
    {
      "repo_nwo" => Google::Protobuf::Value.new(string_value: T.must(@repository).name_with_display_owner),
      "pr_number" => Google::Protobuf::Value.new(string_value: T.must(@pull_request).number.to_s),
      "pr_title" => Google::Protobuf::Value.new(string_value: T.must(@pull_request).title),
      "agent_id" => Google::Protobuf::Value.new(string_value: @message[:agent_id].to_s)
    }
  end
end
