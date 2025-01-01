# typed: strict
# frozen_string_literal: true

class Hook::Payload::IssueDependenciesPayload < Hook::Payload
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_payload_hash
    {
      action: hook_event.action,
      blocked_issue_id: hook_event.blocked_issue_id,
      blocked_issue: api_serialize(:issue_hash, hook_event.blocked_issue),
      blocked_issue_repo: api_serialize(:repository_hash, hook_event.blocked_issue_repository),
      blocking_issue_id: hook_event.blocking_issue_id,
      blocking_issue: api_serialize(:issue_hash, hook_event.blocking_issue),
      blocking_issue_repo: api_serialize(:repository_hash, hook_event.blocking_issue_repository),
    }.compact
  end
end
