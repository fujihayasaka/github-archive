# typed: strict
# frozen_string_literal: true

module CopilotPLG
  class SharedThreadEventProcessor < GitHub::StreamProcessors::SingleMessageProcessor
    DEFAULT_GROUP_ID = T.let("github-#{Rails.env}-copilot_plg-shared_thread_event_processor", String)
    DEFAULT_SUBSCRIBE_TO = /copilot\.api\.v0\.SharedThreadEvent\Z/

    options[:session_timeout] = 60.seconds
    options[:socket_timeout] = 65.seconds
    options[:start_from_beginning] = false

    sig { params(kwargs: T.untyped).void }
    def setup(**kwargs)
      options[:group_id] ||= DEFAULT_GROUP_ID
      options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
    end

    sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
    def process_message(message)
      event_type, shared_id = message.value.values_at(:event_type, :shared_id)

      return message.skip(:unknown_event_type) if event_type == :EVENT_TYPE_UNKNOWN
      return message.skip(:missing_shared_id) if shared_id.blank?

      stats.increment("copilot_plg.shared_thread_event", tags: ["event_type:#{event_type.downcase}"])

      GitHub::WebSocket.notify_copilot_shared_thread_channel(
        GitHub::WebSocket::Channels.copilot_shared_thread(shared_id),
        { event_type: event_type.to_s },
      )
    end
  end
end
