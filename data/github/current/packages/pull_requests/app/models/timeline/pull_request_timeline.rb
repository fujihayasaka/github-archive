# typed: strict
# frozen_string_literal: true

class Timeline::PullRequestTimeline < Timeline::BaseTimeline
  include GitHub::Memoizer

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
  sig { override.returns(Promise[T::Array[Timeline::Placeholder::Base]]) }
  memoize def async_placeholders
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

    Promise.all(placeholders).then(&:flatten)
  end

  sig { returns(Promise[Timeline::IssueTimeline]) }
  memoize def async_issue_timeline
    subject.async_issue.then do |issue|
      T.must(issue).timeline_model_for(viewer, filter_options)
    end
  end

  sig { returns(Promise[T::Array[Timeline::Placeholder::Base]]) }
  def async_issue_comment_placeholders
    async_issue_timeline.then(&:async_issue_comment_placeholders)
  end


  sig { params(requested_issue_event_type_names: T::Array[String]).returns(Promise[T::Array[Timeline::Placeholder::Base]]) }
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

  sig { returns(Promise[T::Array[Timeline::Placeholder::Base]]) }
  def async_cross_reference_placeholders
    async_issue_timeline.then(&:async_cross_reference_placeholders)
  end

  sig { returns(Promise[T::Array[Timeline::Placeholder::Base]]) }
  def async_pull_request_commit_placeholders
    # When the feature flag is enabled, do not request commit events for logged-out users
    if viewer.nil? && hide_commits_from_logged_out_users_enabled?
      return T.unsafe(Promise.resolve([]))
    end

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

  sig { returns(Promise[T::Array[Timeline::Placeholder::Base]]) }
  def async_pull_request_revision_marker_placeholders
    return T.unsafe(Promise.resolve([])) if viewer.nil?

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

  sig { returns(Promise[T::Array[Timeline::Placeholder::Base]]) }
  def async_pull_request_review_placeholders
    Platform::Loaders::Timeline::Placeholders::PullRequestReview.load(subject.id, viewer)
  end

  sig { returns(Promise[T::Array[Timeline::Placeholder::Base]]) }
  def async_legacy_pull_request_review_thread_placeholders
    Platform::Loaders::Timeline::Placeholders::LegacyPullRequestReviewThread.load(subject.id, viewer)
  end

  private

  sig { override.returns(PullRequest) }
  def subject
    super
  end

  sig { params(commits: T::Array[T.untyped]).returns(T::Array[Timeline::Placeholder::PullRequestCommit]) }
  def build_pull_request_commit_placeholders(commits)
    commits.map do |commit|
      Timeline::Placeholder::PullRequestCommit.new(
        id: Platform::Models::PullRequestCommit.id_for(subject, commit),
        sort_datetimes: commit.timeline_sort_by,
        commit: commit,
        pull_request: subject,
      )
    end
  end

  sig { returns(T::Array[String]) }
  def requested_issue_event_type_names
    requested_item_type_names - NON_ISSUE_EVENT_TYPE_NAMES
  end

  sig { returns(T::Boolean) }
  def hide_commits_from_logged_out_users_enabled?
    T.must(subject.repository).feature_enabled?(:hide_commits_from_logged_out_users)
  end
end
