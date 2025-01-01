# typed: true
# frozen_string_literal: true

class Hook::Payload::SlashCommandPayload < Hook::Payload
  def to_payload_hash
    {
      action: hook_event.action,
      command: hook_event.command,
      issue_comment: api_serialize(:issue_comment_hash, hook_event.target)
    }
  end
end
