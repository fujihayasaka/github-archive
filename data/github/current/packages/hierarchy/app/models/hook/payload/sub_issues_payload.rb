# typed: strict
# frozen_string_literal: true

class Hook::Payload::SubIssuesPayload < Hook::Payload
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_payload_hash
    {
      action: hook_event.action,
      sub_issue_id: hook_event.child_issue_id,
      sub_issue: api_serialize(:issue_hash, hook_event.sub_issue),
      sub_issue_repo: api_serialize(:repository_hash, hook_event.sub_issue_repository),
      parent_issue_id: hook_event.parent_issue_id,
      parent_issue: api_serialize(:issue_hash, hook_event.parent_issue),
      parent_issue_repo: api_serialize(:repository_hash, hook_event.parent_issue_repository),
    }.compact
  end
end
