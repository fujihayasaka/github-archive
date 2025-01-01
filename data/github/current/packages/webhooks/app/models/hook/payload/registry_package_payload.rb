# typed: true
# frozen_string_literal: true

class Hook::Payload::RegistryPackagePayload < Hook::Payload

  def to_payload_hash
    {
      action: hook_event.action,
      registry_package: api_serialize(:registry_package_hash, hook_event),
    }
  end

end
