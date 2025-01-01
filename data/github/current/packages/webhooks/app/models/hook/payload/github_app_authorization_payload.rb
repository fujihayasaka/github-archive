# typed: true
# frozen_string_literal: true

class Hook::Payload::GitHubAppAuthorizationPayload < Hook::Payload
  def to_payload_hash
    {}.tap do |opts|
      opts[:action] = hook_event.action
    end
  end
end
