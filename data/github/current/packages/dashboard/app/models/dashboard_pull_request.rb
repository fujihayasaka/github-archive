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
      author: pull_request.safe_user.display_login,
      title: pull_request.title,
      id: pull_request.id,
      number: pull_request.number,
      createdAt: pull_request.created_at,
      updatedAt: pull_request.updated_at,
      permalink: pull_request.permalink,
      commentCount: pull_request.total_comments,
      suggestedAction: suggested_action,
      headSha: pull_request.head_sha,
      repoNameWithOwner: repository_nwo_payload,
      isDraft: pull_request.draft?,
      inMergeQueue: pull_request.in_merge_queue?,
      readByCurrentUser: pull_request.issue.read_by_current_user,
      repository: repository_payload,
      assignees: pull_request.assignees.map { |assignee| { login: assignee.display_login, avatarUrl: assignee.primary_avatar_url } },
      assignedToCopilot: assigned_to_copilot?,
      viewerCanRequestCopilotCodeReview: can_request_copilot_code_review?
    }
  end

  def ==(other)
    self.pull_request == other.pull_request
  end

  def suggested_action
    return nil unless FeatureFlag.vexi.enabled?(:dashboard_pr_list_suggested_actions, viewer, default: false)
    return nil if pull_request.draft? || pull_request.closed? || pull_request.in_merge_queue?
    return nil if !viewer_is_author?

    if pull_request.review_requests.empty? && pull_request.reviews.empty?
      return "Request a review"
    elsif pull_request.conflict
      return "Resolve conflicts"
    end

    enforceable_reviews = pull_request.latest_enforced_reviews(writers_only: false)
    return "Address feedback" if enforceable_reviews.any?(&:changes_requested?)

    use_unified_predicate = unified_has_suggestion_predicate_enabled?
    comments_contain_suggestion = pull_request.async_review_comments.then do |comments|
      GitHub::PrefillAssociations.prefill_associations(comments, :automated_review_comment) if use_unified_predicate

      comments.any? do |comment|
        comment_has_suggestion?(comment, use_unified_predicate) && !comment.pull_request_review_thread.resolved?
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

  attr_reader :pull_request, :viewer

  def comment_has_suggestion?(comment, use_unified_predicate)
    if use_unified_predicate
      comment.has_suggestion?(require_preload: true)
    else
      comment.body_may_contain_suggestion?
    end
  end

  def unified_has_suggestion_predicate_enabled?
    FeatureFlag.vexi.enabled?(
      :unified_batch_pr_comments,
      [viewer, pull_request.repository, pull_request.repository&.owner].compact,
      default: false
    )
  end

  def viewer_is_author?
    return false unless viewer

    pull_request.user == viewer
  end

  def repository_payload
    current_user_can_push = pull_request.repository.authorized_to_write?(viewer)
    Repos::ReactPayload.current_repository_payload(pull_request.repository, current_user_can_push:)
  end

  def repository_nwo_payload
    Repos::ReactPayload.current_repository_nwo_payload(pull_request.repository)
  end

  sig { returns T::Boolean }
  def assigned_to_copilot?
    copilot = copilot_integration&.bot

    copilot.present? && pull_request.assignees.include?(copilot)
  end

  sig { returns T.nilable(Integration) }
  def copilot_integration
    @copilot_integration ||= Apps::Privileged.integration(:copilot_swe_agent)
  end

  sig { returns T::Boolean }
  def can_request_copilot_code_review?
    current_repository = pull_request.repository
    copilot_code_review_access = PullRequests::Copilot::CodeReviewAccess.new(actor: viewer, current_repository:, pull_request:)
    copilot_code_review_access.can_create_review_request?
  end
end
