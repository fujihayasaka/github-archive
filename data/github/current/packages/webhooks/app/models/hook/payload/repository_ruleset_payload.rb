# typed: true
# frozen_string_literal: true

class Hook::Payload::RepositoryRulesetPayload < Hook::Payload
  def to_payload_hash
    {}.tap do |payload|
      payload[:action] = hook_event.action
      payload[:repository_ruleset] = Api::Serializer.serialize(:repository_ruleset_hash, hook_event.repository_ruleset, request_source: hook_event.repository_ruleset.source)
      payload[:changes] = hook_event.changes if hook_event.changes
    end
  end
end
