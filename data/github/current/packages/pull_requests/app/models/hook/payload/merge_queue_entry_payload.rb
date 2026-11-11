# typed: true
# frozen_string_literal: true

class Hook::Payload::MergeQueueEntryPayload < Hook::Payload
  def to_payload_hash
    {
      action: hook_event.action,
      merge_queue: api_serialize(:merge_queue_hash, hook_event.merge_queue),
      merge_queue_entry: api_serialize(:merge_queue_entry_hash, hook_event.merge_queue_entry),
      pull_request: api_serialize(:pull_request_hash, hook_event.pull_request),
      message: hook_event.message,
    }
  end
end
