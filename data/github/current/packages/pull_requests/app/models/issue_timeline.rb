# typed: true
# frozen_string_literal: true

# Timeline behavior which applies to Issues and Pull Requests.
module IssueTimeline
  extend T::Helpers

  # Public: Preloads #issue and #repository associations in IssueEvent
  # objects, as well as IssueComment, CrossReference, and Commit objects
  # on an Issue or PullRequest timeline.
  def self.prefill(timeline, current_user: nil, repository: nil, preload_comment_edits: false)
    grouped = timeline.group_by do |item|
      case item
      when Platform::Models::PullRequestCommit
        :commits
      when CrossReference
        :cross_references
      when IssueComment
        :issue_comments
      when CommitCommentThread
        :commit_comment_threads
      when PullRequestReview
        :reviews
      when DeprecatedPullRequestReviewThread
        :deprecated_review_threads
      when PullRequestReviewThread
        :review_threads
      when PullRequestRevisionMarker
        :pull_request_review_marker
      when IssueEvent
        :events
      else
        :no_prefill
      end
    end

    if grouped[:events]
      IssueEventPrefiller.prefill(grouped[:events], prefill_repository_owner: true)  # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    if grouped[:commits]
      Commit.prefill_verified_signature(grouped[:commits].map(&:commit))

      # Do we need this? PullRequest#changed_commits already prefills users
      Commit.prefill_users(grouped[:commits].map(&:commit))
    end

    if grouped[:cross_references]
      CrossReference.prefill_associations(grouped[:cross_references], current_user: current_user, exclude_prefills: [:author_association]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    if grouped[:issue_comments]
      # Use existing prefill data from the prefilled events, if available.
      available_records = grouped[:events]&.map(&:repository) || []
      available_records += grouped[:events]&.map(&:issue) || []
      available_records += grouped[:events]&.map(&:actor) || []
      available_records.uniq!

      IssueComment.prefill_associations(grouped[:issue_comments], exclude_prefills: [:author_association], preload_comment_edits: preload_comment_edits, current_user: current_user, available_records: available_records) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    if grouped[:reviews]
      GitHub::PrefillAssociations.prefill_associations(grouped[:reviews], [:repository, :user, :pull_request])
    end

    if grouped[:deprecated_review_threads]
      grouped[:deprecated_review_threads].each do |thread|
        PullRequestReviewComment.prefill_associations(thread.comments, issue: thread.pull.issue, repository: thread.repository)
      end
    end

    if grouped[:review_threads]
      grouped[:review_threads].each do |thread|
        PullRequestReviewComment.prefill_associations(thread.comments, issue: thread.pull_request.issue, repository: thread.repository) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end

    cross_references = grouped[:cross_references] || []
    associables = (cross_references.map(&:source) + cross_references.map(&:target)).uniq
    associables += grouped[:issue_comments] || []
    IssuePrefiller.optimized_preload_author_associations(associables, current_user)
  end

  # Public: Grab all timeline items sorted by creation time
  #
  # viewer - the User that is viewing the conversation (current_user)
  # since  - optional Time to restrict showing only more-recent items
  #
  # Returns an Array of items.
  def timeline_for(viewer, since: nil, all_valid_events: false, filter_options: {})
    T.bind(self, T.any(Issue, PullRequest))
    Platform::Security::RepositoryAccess.with_viewer(viewer) do
      filter_options = {
        since: since,
        visible_events_only: !all_valid_events,
        filter_closed_if_preceded_by_merged: !all_valid_events && self.respond_to?(:merged?) && T.unsafe(self).merged?
      }.merge(filter_options)
      timeline_items = timeline_model_for(viewer, filter_options).async_values.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      IssueTimeline::LegacyAdapter.new(timeline_items, viewer).call
    end
  end

  # Internal: To use the new timeline in `app/models/timeline/` as a drop-in replacement for this
  #   old implementation, we need to do some additional steps which will not become part of the
  #   new implementation but move to other places (like the UI). This class collects all these
  #   steps to make them them easier to spot, understand and dispose.
  class LegacyAdapter
    def initialize(original_timeline_items, viewer)
      @original_timeline_items = original_timeline_items
      @viewer = viewer
    end

    def call
      map_commit_comment_threads(original_timeline_items, viewer)
    end

    private

    attr_reader :original_timeline_items, :viewer

    def map_commit_comment_threads(timeline_items, viewer)
      Promise.all(timeline_items.map do |item|
        if item.is_a?(Platform::Models::PullRequestCommitCommentThread)
          item.async_to_commit_comment_thread(viewer)
        else
          item
        end
      end).sync
    end
  end
end
