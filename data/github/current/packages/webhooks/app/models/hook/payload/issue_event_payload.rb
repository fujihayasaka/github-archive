# typed: true
# frozen_string_literal: true

class Hook::Payload::IssueEventPayload < Hook::Payload

  # In addition to any keys defined here, The `target_repository`,
  # `target_organization`, and `actor` from the event will be mixed in as
  # `repository`, `organization`, and `sender` respectively.
  def to_payload_hash
    {
      action: hook_event.action,
      event_name: hook_event.event_name,
      target: api_serialize(:issue_event_hash, hook_event.target),
      issue_url: hook_event.issue.present? ? api_serialize(:issue_hash, hook_event.issue)&.dig(:url) : nil,
      issue_html_url: hook_event.issue.present? ? api_serialize(:issue_hash, hook_event.issue)&.dig(:html_url) : nil,
      actor_url: api_serialize(:simple_user_hash, hook_event.actor)[:url],
      actor_html_url: api_serialize(:simple_user_hash, hook_event.actor)[:html_url],
      commit: hook_event.commit_id,
      commit_repository_url: hook_event.commit_repository.present? ? api_serialize(:repository_hash, hook_event.commit_repository)&.dig(:url) : nil,
      commit_repository_html_url: hook_event.commit_repository.present? ? api_serialize(:repository_hash, hook_event.commit_repository)&.dig(:html_url) : nil,
      referencing_issue_url: hook_event.referencing_issue.present? ? api_serialize(:issue_hash, hook_event.referencing_issue).dig(:url) : nil,
      referencing_issue_html_url: hook_event.referencing_issue.present? ? api_serialize(:issue_hash, hook_event.referencing_issue).dig(:html_url) : nil,
      performed_by_integration_id: hook_event.performed_by_integration_id,
    }.merge(event_html_url(hook_event))
  end

  def event_html_url(hook_event)
    # Don't set html_url if issue_id is missing. Issue events are normally
    # associated to issues but there isn't a strict validation check enforcing
    # that all events must have an issue_id associated with them. If we can't
    # find an issue_id associated with the event, the event is likely to be hidden
    # from the UI anyway so don't return an html_url for it. We can't return an HTML
    # url without having that issue_id.
    return {} unless hook_event.issue_id.present?

    issue_numbers_by_id = ::Issues.domain.numbers_by_ids(hook_event.repository_id, [hook_event.issue_id])
    is_pull_request_by_id = ::Issues.domain.is_pull_request_by_ids([hook_event.issue_id])

    # If we can't get the issue ID or PR ID, don't add html_url field
    return {} unless [issue_numbers_by_id, is_pull_request_by_id].all?(&:present?)

    repository = hook_event.repository
    issue_number = issue_numbers_by_id[hook_event.issue_id]

    url_path = if is_pull_request_by_id[hook_event.issue_id]
      "/#{repository.owner_display_login}/#{repository.name}/pull/#{issue_number}"
    else
      "/#{repository.owner_display_login}/#{repository.name}/issues/#{issue_number}"
    end
    event_url_path = "#{url_path}#event-#{hook_event.target_id}"

    {
      event_html_url: "#{GitHub.url}#{event_url_path}"
    }
  end
end
