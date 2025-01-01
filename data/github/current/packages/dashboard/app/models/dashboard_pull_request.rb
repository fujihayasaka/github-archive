# typed: true
# frozen_string_literal: true

# A pull request displayed on the dashboard above the home feed.
class DashboardPullRequest
  def initialize(pull_request, viewer:)
    @pull_request = pull_request
    @viewer = viewer
  end

  def to_h
    {
      author: pull_request.user.display_login,
      title: pull_request.title,
      id: pull_request.id,
      number: pull_request.number,
      updatedAt: pull_request.updated_at,
      permalink: pull_request.permalink,
      commentCount: pull_request.total_comments,
      suggestedAction: suggested_action,
      headSha: pull_request.head_sha,
      repoNameWithOwner: {
        name: pull_request.repository.name,
        ownerLogin: pull_request.repository.owner.display_login,
      },
      isDraft: pull_request.draft?,
      inMergeQueue: pull_request.in_merge_queue?,
      readByCurrentUser: pull_request.issue.read_by_current_user,
    }
  end

  def ==(other)
    self.pull_request == other.pull_request
  end

  def suggested_action
    return nil if pull_request.draft? || pull_request.closed? || pull_request.in_merge_queue?
    return nil if !viewer_is_author?

    if pull_request.review_requests.empty? && pull_request.reviews.empty?
      return "Request a review"
    elsif pull_request.conflict
      return "Resolve conflicts"
    end

    enforceable_reviews = pull_request.latest_enforced_reviews(writers_only: false)
    return "Address feedback" if enforceable_reviews.any?(&:changes_requested?)

    comments_contain_suggestion = pull_request.async_review_comments.then do |comments|
      comments.any? do |comment|
        comment.body_may_contain_suggestion? && !comment.pull_request_review_thread.resolved?
      end
    end.sync
    return "Apply suggestions" if comments_contain_suggestion

    threads_unresolved = pull_request.async_review_threads.then do |threads|
      threads.any? { |thread| !thread.resolved? }
    end.sync
    return "Resolve conversations" if threads_unresolved

    if pull_request.currently_mergeable? && enforceable_reviews.any?(&:approved?)
      "Merge"
    elsif pull_request.review_requests.pending.any?
      "Waiting on reviewers"
    end
  end

  private

  attr_reader :pull_request

  def viewer_is_author?
    return false unless @viewer

    pull_request.user == @viewer
  end
end
