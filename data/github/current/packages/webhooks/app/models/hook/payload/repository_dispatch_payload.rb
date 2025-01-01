# typed: true
# frozen_string_literal: true

class Hook::Payload::RepositoryDispatchPayload < Hook::Payload

  def to_payload_hash
    {
      # We do a double lookup here, because there is a possible race condition between the two versions of code(old without the "user_action") and new(with the "user_action")
      # Upon deploy of this we can have events being instrumented in the queue that conform the old contract(missing "user_action").
      action: hook_event.user_action || hook_event.action,
      branch: hook_event.branch,
      client_payload: hook_event&.client_payload,
    }
  end

end
