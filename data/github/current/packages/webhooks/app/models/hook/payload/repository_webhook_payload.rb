# typed: true
# frozen_string_literal: true

class Hook::Payload::RepositoryWebhookPayload < Hook::Payload
  def to_payload_hash
    {
      action: hook_event.action,
      hook: api_serialize(:repo_hook_hash, hook_event.hook),
    }.tap do |payload|
      payload[:hook][:updated_at] = hook_event.updated_at.iso8601 if hook_event.updated_at
    end
  end
end
