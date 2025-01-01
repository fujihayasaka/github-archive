# typed: true
# frozen_string_literal: true

class Hook::Payload::PublicPayload < Hook::Payload

  def to_payload_hash
    {} # repository will be mixed in automatically
  end

end
