# typed: true
# frozen_string_literal: true

class Hook::Payload::DeletePayload < Hook::Payload

  def to_payload_hash
    {
      ref: hook_event.branch_or_tag_name,
      ref_type: hook_event.ref_type,
      pusher_type: hook_event.pusher_type,
    }
  end

end
