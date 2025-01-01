# typed: true
# frozen_string_literal: true

module Api::App::PullRequestReviewCommentPositioningDependency
  extend T::Helpers

  requires_ancestor { Api::App }

  def filter_and_sort(scope)
    # filter by updated_at
    if (since = params[:since]).present?
      since = parse_time!(since).getlocal
      scope = scope.since(since)
    end

    if (sort = params[:sort]).present?
      direction = params[:direction] || "asc"
      scope = scope.sorted_by sort, direction
    else
      scope = scope.sorted_by "id", "asc"
    end

    scope
  end

  def pull_review_comments(review_comments, include_pending: false)
    scope = review_comments
    scope = scope.select(:id)
    scope = scope.filter_spam_for(current_user)
    scope = filter_and_sort(scope)
    # Remove pending review comments.
    scope = scope.with_submitted_state unless include_pending

    scope = paginate_rel(scope)
    paginator.collection_size = scope.total_entries

    review_comments_ids = scope.pluck(:id)
    filtered_and_sorted_comments = filter_and_sort(review_comments.where(id: review_comments_ids).includes(:pull_request_review_thread, :pull_request))
    filtered_and_sorted_comments.select { |review_comment| review_comment.pull_request.present? }
  end

  def prefill_legacy_positioning(review_comments)
    review_comments.map(&:pull_request_review_thread).uniq.group_by(&:pull_request).each do |pull_request, threads|
      PullRequests::CommentPosition.preload_positionings_for_threads(pull_request:, threads:)
    end
  end

  def prefill_review_comments(repo, review_comments)
    PullRequestReviewComment.prefill_associations(review_comments)
    Reaction::Summary.prefill(review_comments)

    prefill_legacy_positioning(review_comments) if repo.feature_flag_enabled?(:pull_requests_rest_serialize_new_positioning, default: false)
  end
end
