# typed: true
# frozen_string_literal: true

class Hook::Payload::TeamAddPayload < Hook::Payload

  def to_payload_hash
    {
      team: api_serialize(:team_hash, hook_event.team)
    }
  end

end
