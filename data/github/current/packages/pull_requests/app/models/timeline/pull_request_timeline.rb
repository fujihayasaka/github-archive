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

  # Public: When the pulls_timeline_limit_issue_events feature flag is enabled,
  # use a cheap DB COUNT(*) query instead of counting all loaded placeholders.
  # This can avoid loading 100k+ events into memory just to get a count.
  #
  # This method is defined directly (not via `memoize`) and handles its own
  # caching to properly override the base class's memoized version.
  sig { override.returns(Promise[Integer]) }
  def async_total_count
    if FeatureFlag.vexi.enabled?(:pulls_timeline_limit_issue_events, subject.repository, default: false)
      return T.must(@_pr_total_count) if defined?(@_pr_total_count)
      @_pr_total_count = T.let(async_real_total_count, T.nilable(Promise[Integer]))
      T.must(@_pr_total_count)
    else
      super
    end
  end

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

  # Internal: Gets the real total count of timeline items using cheap DB
  # COUNT queries instead of loading all events into memory.
  #
  # Counts visible issue events, subtracts deployment events that lack a
  # deployment_id in their IssueEventDetail (matching filter_deployed_events!
  # behavior), and adds DB counts for non-event items (comments, reviews, and cross references).
  sig { returns(Promise[Integer]) }
  def async_real_total_count
    issue = T.must(subject.issue)
    issue_scope = issue.events

    # Count visible events minus deployment events without valid details
    non_deployment_count = issue_scope
      .where(event: ::IssueEvent::VISIBLE_EVENTS - ::IssueEvent::Loader::DEPLOYMENT_EVENTS)
      .count
    valid_deployment_count = IssueEventDetail
      .where(issue_event_id: issue_scope.where(event: ::IssueEvent::Loader::DEPLOYMENT_EVENTS).select(:id))
      .where.not(deployment_id: nil)
      .count
    issue_event_count = non_deployment_count + valid_deployment_count

    # Count non-event items via DB queries (comments, reviews, cross-references, commits)
    # to avoid triggering placeholder loaders outside of security context
    comment_count = IssueComment.where(issue_id: issue.id).count
    review_count = subject.reviews.count
    cross_reference_count = CrossReference.where(target: issue).count
    commit_count = subject.changed_commits.size

    Promise.resolve(issue_event_count + comment_count + review_count + cross_reference_count + commit_count)
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
end
