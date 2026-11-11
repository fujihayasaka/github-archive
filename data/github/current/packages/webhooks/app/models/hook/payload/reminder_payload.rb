# typed: true
# frozen_string_literal: true

class Hook::Payload::ReminderPayload < Hook::Payload
  def to_payload_hash
    {
      action: hook_event.action,
      context: api_serialize(:reminder_context_hash,
        hook_event.reminder_event_context,
        event_type: hook_event.reminder_event_type,
        repository: hook_event.target_repository,
      ),
      event_at: Api::Serializer.time(hook_event.event_at),
      pull_requests: hook_event.pull_requests.map { |pull_request| api_serialize(:pull_request_hash, pull_request, hook: true) },
      pull_requests_for_author: hook_event.pull_requests_for_author.map { |pull_request| api_serialize(:pull_request_hash, pull_request, hook: true) },
      reminder: api_serialize(:reminder_hash, hook_event.reminder),
    }
  end
end
