# typed: strict
# frozen_string_literal: true

class Hook::Payload::IssueDependenciesPayload < Hook::Payload
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_payload_hash
    # Security: Exclude cross-repository issue details to prevent information disclosure.
    # Webhooks are repository-scoped and don't have user context to verify access.
    payload = { action: hook_event.action }

    if cross_repository_dependency?
      add_target_repo_issue_only(payload)
    else
      payload.merge!(
        blocked_issue_id: hook_event.blocked_issue_id,
        blocked_issue: api_serialize(:issue_hash, hook_event.blocked_issue),
        blocked_issue_repo: api_serialize(:repository_hash, hook_event.blocked_issue_repository),
        blocking_issue_id: hook_event.blocking_issue_id,
        blocking_issue: api_serialize(:issue_hash, hook_event.blocking_issue),
        blocking_issue_repo: api_serialize(:repository_hash, hook_event.blocking_issue_repository),
      )
    end

    payload.compact
  end

  private

  sig { returns(T::Boolean) }
  def cross_repository_dependency?
    blocked_repo = hook_event.blocked_issue&.repository
    blocking_repo = hook_event.blocking_issue&.repository
    blocked_repo && blocking_repo && blocked_repo.id != blocking_repo.id
  end

  sig { params(payload: T::Hash[Symbol, T.untyped]).void }
  def add_target_repo_issue_only(payload)
    target_repo = hook_event.target_repository
    return unless target_repo

    blocked_issue = hook_event.blocked_issue
    if blocked_issue&.repository&.id == target_repo.id
      payload[:blocked_issue_id] = hook_event.blocked_issue_id
      payload[:blocked_issue] = api_serialize(:issue_hash, blocked_issue)
    end

    blocking_issue = hook_event.blocking_issue
    if blocking_issue&.repository&.id == target_repo.id
      payload[:blocking_issue_id] = hook_event.blocking_issue_id
      payload[:blocking_issue] = api_serialize(:issue_hash, blocking_issue)
    end
  end
end
