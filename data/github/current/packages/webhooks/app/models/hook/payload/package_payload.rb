# typed: true
# frozen_string_literal: true

class Hook::Payload::PackagePayload < Hook::Payload

  def to_payload_hash
    {
      action: hook_event.action,
      package: api_serialize(:registry_package_hash, hook_event),
    }
  end

end
