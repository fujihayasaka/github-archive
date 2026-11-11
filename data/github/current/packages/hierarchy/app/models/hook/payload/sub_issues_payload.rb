# typed: strict
# frozen_string_literal: true

class Hook::Payload::SubIssuesPayload < Hook::Payload
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_payload_hash
    # Security: Exclude cross-repository issue details to prevent information disclosure.
    # Webhooks are repository-scoped and don't have user context to verify access.
    payload = { action: hook_event.action }

    if cross_repository?
      add_target_repo_issue_only(payload)
    else
      payload.merge!(
        sub_issue_id: hook_event.child_issue_id,
        sub_issue: api_serialize(:issue_hash, hook_event.sub_issue),
        sub_issue_repo: api_serialize(:repository_hash, hook_event.sub_issue_repository),
        parent_issue_id: hook_event.parent_issue_id,
        parent_issue: api_serialize(:issue_hash, hook_event.parent_issue),
        parent_issue_repo: api_serialize(:repository_hash, hook_event.parent_issue_repository),
      )
    end

    payload.compact
  end

  private

  sig { returns(T::Boolean) }
  def cross_repository?
    sub_repo = hook_event.sub_issue&.repository
    parent_repo = hook_event.parent_issue&.repository
    sub_repo && parent_repo && sub_repo.id != parent_repo.id
  end

  sig { params(payload: T::Hash[Symbol, T.untyped]).void }
  def add_target_repo_issue_only(payload)
    target_repo = hook_event.target_repository
    return unless target_repo

    sub_issue = hook_event.sub_issue
    if sub_issue&.repository&.id == target_repo.id
      payload[:sub_issue_id] = hook_event.child_issue_id
      payload[:sub_issue] = api_serialize(:issue_hash, sub_issue)
    end

    parent_issue = hook_event.parent_issue
    if parent_issue&.repository&.id == target_repo.id
      payload[:parent_issue_id] = hook_event.parent_issue_id
      payload[:parent_issue] = api_serialize(:issue_hash, parent_issue)
    end
  end
end
