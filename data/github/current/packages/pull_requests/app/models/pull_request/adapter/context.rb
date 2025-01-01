# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::Context < Issue::Adapter::Context
  BASE_REF_CHANGED_EVENT = "base_ref_changed"
  CONVERT_TO_DRAFT_EVENT = "convert_to_draft"
  DEPLOYED_EVENT = "deployed"
  READY_FOR_REVIEW_EVENT = "ready_for_review"
  ADDED_TO_MERGE_QUEUE_EVENT = "added_to_merge_queue"
  REMOVED_FROM_MERGE_QUEUE_EVENT = "removed_from_merge_queue"
  DEPLOYMENT_ENVIRONMENT_CHANGED_EVENT = "deployment_environment_changed"

  attr_reader :pull_request
  attr_accessor :commits_by_oid, :reviews_by_id, :commit_comments_by_oid, :legacy_reviews_by_id

  def initialize(pull_request, repository, viewer, cap_filter = nil)
    @pull_request = pull_request
    @issue = pull_request.issue
    @repository = repository
    @viewer = viewer
    @cap_filter = cap_filter
  end

  def raise_on_missing_timeline_adapter
    false
  end

  # These `_events` methods are to ensure proper data preloading
  # See `preloading from PullRequest::ShowLoader` context at PullRequestsTimelineEventsReadyForReviewComponentTest (ex.)
  def deployed_events
    return @deployed_events if defined? @deployed_events
    @deployed_events = events.select { |p| p.event == DEPLOYED_EVENT }
  end

  def ready_for_review_events
    return @ready_for_review_events if defined? @ready_for_review_events
    @ready_for_review_events = events.filter { |event| event.event == READY_FOR_REVIEW_EVENT }
  end

  def convert_to_draft_events
    return @convert_to_draft_events if defined? @convert_to_draft_events
    @convert_to_draft_events = events.filter { |event| event.event == CONVERT_TO_DRAFT_EVENT }
  end

  def base_ref_changed_events
    return @base_ref_changed_events if defined? @base_ref_changed_events
    @base_ref_changed_events = events.filter { |event| event.event == BASE_REF_CHANGED_EVENT }
  end

  def deployment_environment_changed_events
    return @deployment_environment_changed_events if defined? @deployment_environment_changed_events
    @deployment_environment_changed_events = events.filter { |event| event.event == DEPLOYMENT_ENVIRONMENT_CHANGED_EVENT }
  end

  def merge_queue_events
    return @merge_queue_events if defined? @merge_queue_events
    @merge_queue_events = events.filter { |event| event.event == ADDED_TO_MERGE_QUEUE_EVENT || REMOVED_FROM_MERGE_QUEUE_EVENT }
  end
end
