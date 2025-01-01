# typed: true
# frozen_string_literal: true

class Timeline::PullRequestTimeline < Timeline::BaseTimeline
  # Keep in sync with client-side constant in ui/packages/pull-request-viewer/constants/relay.ts
  PAGE_SIZE = 30

  # Internal: List of Platform type names which are not backed by the `IssueEvent` model
  NON_ISSUE_EVENT_TYPE_NAMES = %w(
    IssueComment
    CrossReferencedEvent
    PullRequestCommit
    PullRequestCommitCommentThread
    PullRequestReview
    PullRequestReviewThread
    PullRequestRevisionMarker
  ).freeze

  # Internal: Compiles the unsorted list of timeline placeholders for pull requests.
  def async_placeholders
    return @placeholders if defined?(@placeholders)

    placeholders = []

    if requested_item_type_names.include?("IssueComment")
      placeholders.push async_issue_comment_placeholders
    end

    if requested_item_type_names.include?("CrossReferencedEvent")
      placeholders.push async_cross_reference_placeholders
    end

    if requested_item_type_names.include?("PullRequestCommit")
      placeholders.push async_pull_request_commit_placeholders
    end

    if requested_item_type_names.include?("PullRequestReview")
      placeholders.push async_pull_request_review_placeholders
    end

    if requested_item_type_names.include?("PullRequestReviewThread")
      placeholders.push async_legacy_pull_request_review_thread_placeholders
    end

    if requested_item_type_names.include?("PullRequestRevisionMarker")
      placeholders.push async_pull_request_revision_marker_placeholders
    end

    unless requested_issue_event_type_names.empty?
      placeholders.push async_issue_event_placeholders(requested_issue_event_type_names: requested_issue_event_type_names)
    end

    @placeholders = Promise.all(placeholders).then(&:flatten)
  end

  def async_issue_timeline
    return @async_issue_timeline if defined?(@async_issue_timeline)

    @async_issue_timeline = subject.async_issue.then do |issue|
      issue.timeline_model_for(viewer, filter_options)
    end
  end

  def async_issue_comment_placeholders
    async_issue_timeline.then(&:async_issue_comment_placeholders)
  end

  def async_issue_event_placeholders(requested_issue_event_type_names: [])
    Promise.all([
      async_issue_timeline.then { |timeline| timeline.async_issue_event_placeholders(requested_issue_event_type_names: requested_issue_event_type_names) },
      async_pull_request_commit_placeholders,
    ]).then do |issue_events_placeholders, pull_request_commit_placeholders|
      IssueEventsFilter.new(
        issue_events_placeholders,
        pull_request_commit_placeholders,
        viewer: viewer,
        pull_request: subject,
        filter_closed_if_preceded_by_merged: filter_options[:filter_closed_if_preceded_by_merged],
      ).call
    end
  end

  def async_cross_reference_placeholders
    async_issue_timeline.then(&:async_cross_reference_placeholders)
  end

  def async_pull_request_commit_placeholders
    subject.async_historical_comparison.then(&:async_commits).then do |commits|
      build_pull_request_commit_placeholders(commits)
    end.catch do |error|
      case error
      when GitRPC::ObjectMissing, GitRPC::CommandFailed, Repository::CommandFailed, GitHub::DGit::UnroutedError
        []
      else
        # don't leak sensitive commit information to sentry
        raise error, "Something went wrong"
      end
    end
  end

  def async_pull_request_revision_marker_placeholders
    return Promise.resolve([]) if viewer.nil?

    Promise.all([
      Platform::Loaders::Timeline::Placeholders::PullRequestRevisionMarker.load(subject.id, viewer),
      async_pull_request_commit_placeholders,
    ]).then do |marker_placeholders, commit_placeholders|
      marker_placeholders.each do |placeholder|
        placeholder.pull_request = subject
      end

      PullRequestRevisionMarkerFilter.new(
        marker_placeholders,
        commit_placeholders,
        viewer,
      ).async_call
    end
  end

  def async_pull_request_review_placeholders
    Platform::Loaders::Timeline::Placeholders::PullRequestReview.load(subject.id, viewer)
  end

  def async_legacy_pull_request_review_thread_placeholders
    Platform::Loaders::Timeline::Placeholders::LegacyPullRequestReviewThread.load(subject.id, viewer)
  end

  private

  def build_pull_request_commit_placeholders(commits)
    commits.map do |commit|
      Timeline::Placeholder::PullRequestCommit.new(
        id: Platform::Models::PullRequestCommit.id_for(subject, commit),
        sort_datetimes: commit.timeline_sort_by,
        oid: commit.oid,
        author_email: commit.author_email,
        pull_request: subject,
      )
    end
  end

  def requested_issue_event_type_names
    requested_item_type_names - NON_ISSUE_EVENT_TYPE_NAMES
  end
end
