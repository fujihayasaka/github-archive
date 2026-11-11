# typed: true
# frozen_string_literal: true

class Hook::Payload::CacheSyncPayload < Hook::Payload

  def to_payload_hash
    {
      cache_location: hook_event.cache_location,
      ref: hook_event.ref_update[:ref],
      before: hook_event.ref_update[:before],
      after: hook_event.ref_update[:after],
    }
  end

end
