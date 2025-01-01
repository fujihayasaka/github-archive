# typed: true
# frozen_string_literal: true

class Api::IssueTimeline < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::Issues::EnsureIssuesEnabled
  include Issues::Domain::Provider

  # These types of timeline items should not (yet) appear in API responses.
  EXCLUDED_ITEMS = [
    PullRequestRevisionMarker,
  ]

  # Get timeline for an Issue
  get "/repositories/:repository_id/issues/:issue_number/timeline", operation_id: "issues/list-events-for-timeline" do
    repo = find_repo!
    issue = issues_domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)
    record_or_404(issue)
    issue = T.cast(issue, Issue)

    set_context_controller_action(issue, "list-events-for-timeline")

    control_access :list_issue_timeline,
      resource: issue,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_issues_enabled_or_pr! repo, issue

    # Issue and PullRequest include different events on their timeline, make sure to
    # deliver the right set of events.
    record = issue.pull_request? ? issue.pull_request : issue
    timeline = T.must(record).timeline_for(current_user, all_valid_events: true).paginate(pagination)

    IssueTimeline.prefill(timeline)

    # filtering out items after prefilling timeline associations to prevent n+1 queries in
    # the filtration method, this could lead to paginated results returning fewer items if
    # a request is made with a scopeless token against an issue with a good number of
    # cross reference events.
    timeline.reject! { |item| exclude_item?(item) }

    deliver :issue_timeline_hash, timeline, repo: repo
  end

  private

  def exclude_item?(item)
    case item.class.to_s
    when "CrossReference"
      !repo_scope? && item.source.repository.private?
    when "PullRequestRevisionMarker"
      true
    else
      false
    end
  end

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def repo_scope?
    @repo_scope ||= Api::AccessControl.scope?(current_user, "repo")
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator
end
