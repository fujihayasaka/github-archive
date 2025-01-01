# typed: true
# frozen_string_literal: true

module IssueUpdate
  extend T::Helpers

  requires_ancestor { IssuesController }

  include IssuesHelper, PullRequests::PageTitleHelper

  def issue_update_payload(item, errors = [])
    item.preload_hierarchy(viewer: current_user) if GitHub::flipper[:tasklist_block_precache].enabled?(current_issue.repository.owner)

    payload = {
      issue_title: item.title,
      source: item.body,
      body: item.body_html(context: { viewer: current_user, cap_filter: cap_filter, unfurl_references: true }),
      newBodyVersion: item.body_version,
      editUrl: show_comment_edit_history_path(item.global_relay_id),
      errors: errors
    }

    if item.pull_request?
      payload[:page_title] = pull_request_page_title(item)
      payload[:default_squash_commit_title] = item.pull_request.default_squash_commit_title
      payload[:default_merge_commit_title] = item.pull_request.default_merge_commit_title
      payload[:default_squash_commit_message] = item.pull_request.default_squash_commit_message
      payload[:default_merge_commit_message] = item.pull_request.default_merge_commit_message
    else
      payload[:page_title] = issue_page_title(item)
    end

    if item.respond_to?(:labels)
      payload[:labels] = render_to_string(
        partial: "issues/labels",
        object: item.labels,
        formats: [:html],
      )
    end

    payload
  end
end
