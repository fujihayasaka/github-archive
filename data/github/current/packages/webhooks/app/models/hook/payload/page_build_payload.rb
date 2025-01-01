# typed: true
# frozen_string_literal: true

class Hook::Payload::PageBuildPayload < Hook::Payload

  def to_payload_hash
    {
      id: hook_event.page_build_id,
      build: api_serialize(:page_build_hash, hook_event.page_build),
    }
  end

end
