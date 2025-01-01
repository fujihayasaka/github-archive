# typed: true
# frozen_string_literal: true

class Hook::Payload::CloseIssueReferencePayload < Hook::Payload

  # In addition to any keys defined here, The `target_repository`,
  # `target_organization`, and `actor` from the event will be mixed in as
  # `repository`, `organization`, and `sender` respectively.
  def to_payload_hash
    {
      action: hook_event.action,
      close_issue_reference_id: hook_event.close_issue_reference_id,
      issue_id: hook_event.issue_id,
      issue_url: Api::Serializer.serialize(:issue_hash, hook_event.issue)[:url],
      issue_html_url: Api::Serializer.serialize(:issue_hash, hook_event.issue)[:html_url],
      pull_request_id: hook_event.pull_request_id,
      pull_request_url: Api::Serializer.serialize(:pull_request_hash, hook_event.pull_request)[:url],
      pull_request_html_url: Api::Serializer.serialize(:pull_request_hash, hook_event.pull_request)[:html_url],
      pull_request_author_id: hook_event.pull_request_author_id,
      source: hook_event.source,
      referenced_at: Api::Serializer.time(hook_event.referenced_at),
    }
  end
end
