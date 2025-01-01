# typed: true
# frozen_string_literal: true

class Api::IssueTimeline < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::Issues::EnsureIssuesEnabled

  # These types of timeline items should not (yet) appear in API responses.
  EXCLUDED_ITEMS = [
    PullRequestRevisionMarker,
  ]

  LOGICAL_SERVICE_KEY = "timeline.logical_service"

  # Get timeline for an Issue
  get "/repositories/:repository_id/issues/:issue_number/timeline", operation_id: "issues/list-events-for-timeline" do
    repo = find_repo!
    issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)
    record_or_404(issue)
    issue = T.cast(issue, Issue)
    log_issue_id(issue) if FeatureFlag.vexi.enabled?(:api_log_issue_id, default: false)

    set_logical_service(issue)
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

    GitHub.dogstats.distribution_time "api.prefill", tags: ["action:issue_timeline"] do
      options = Api::SerializerOptions.fill(default_options)
      IssueTimeline.prefill(timeline, current_user: current_user, repository: repo, preload_comment_edits: preload_edits?(options))
    end

    # filtering out items after prefilling timeline associations to prevent n+1 queries in
    # the filtration method, this could lead to paginated results returning fewer items if
    # a request is made with a scopeless token against an issue with a good number of
    # cross reference events.
    timeline.reject! { |item| exclude_item?(item) }

    GitHub.dogstats.distribution_time "api.deliver", tags: ["action:issue_timeline"] do
      deliver :issue_timeline_hash, timeline, repo: repo
    end
  end

  private

  def preload_edits?(options)
    params   = options[:mime_params]
    params.include?(:html) || params.include?(:full) || params.include?(:text)
  end

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

  def set_logical_service(issue)
    request.env[LOGICAL_SERVICE_KEY] = if issue.pull_request?
      "#{::GitHub::ServiceMapping::SERVICE_PREFIX}/pull_requests"
    else
      "#{::GitHub::ServiceMapping::SERVICE_PREFIX}/issues"
    end
    push_service_mapping_context
  end

  def logical_service
    request.env[LOGICAL_SERVICE_KEY] || super
  end

  def log_issue_id(issue)
    log_data.update({
      "gh.issue.id" => issue.id,
    })
  end
end
