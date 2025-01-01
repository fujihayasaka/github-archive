# typed: true
# frozen_string_literal: true

class Conduit::Api::Feed < Conduit::Feed
  include GitHub::Memoizer

  def after_build
    GitHub.dogstats.distribution_time("conduit.preload_feed", tags:) do
      preload_labels
      preload_assignees
      preload_pull_requests
    end
    super
  end

  private

  def preload_pull_requests
    pull_requests = pull_requests_by_id.values

    GitHub::PrefillAssociations.prefill_batch_method(
      pull_requests,
      :prelude_changed_commits,
    )

    GitHub::PrefillAssociations.prefill_batch_method( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      pull_requests.map(&:repository),
      :open_issues_count,
    )
  end

  def preload_labels
    label_ids = issue_label_ids + pull_request_label_ids

    cached_records[:labels] ||= Label.where(id: label_ids)
  end

  def preload_assignees
    assignee_ids = issue_assignee_ids + pull_request_assignee_ids

    cached_records[:assignees] ||= User.where(id: assignee_ids)
  end

  memoize def issue_twirp_items
    twirp_items.select do |twirp_item|
      twirp_item.subject_type == :SUBJECT_TYPE_ISSUE
    end
  end

  memoize def pull_request_twirp_items
    twirp_items.select do |twirp_item|
      twirp_item.subject_type == :SUBJECT_TYPE_PULL_REQUEST
    end
  end

  memoize def issue_label_ids
    issue_twirp_items.flat_map do |twirp_item|
      twirp_item.issue_subject.labels.map(&:id)
    end
  end

  memoize def pull_request_label_ids
    pull_request_twirp_items.flat_map do |twirp_item|
      twirp_item.pull_request_subject.labels.map(&:id)
    end
  end

  memoize def issue_assignee_ids
    issue_twirp_items.flat_map do |twirp_item|
      twirp_item.issue_subject.assignees.map(&:id)
    end
  end

  memoize def pull_request_assignee_ids
    pull_request_twirp_items.flat_map do |twirp_item|
      twirp_item.pull_request_subject.assignees.map(&:id)
    end
  end

  def pull_requests_by_id
    @pull_requests_by_id ||= Prelude.wrap(PullRequest.where(id: @pull_request_ids) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      .includes(
        :user,
        :base_user,
        :head_user,
        repository: :owner,
        review_requests_pending: :reviewer,
        base_repository: [:organization, :owner],
        head_repository: :owner,
        issue: [:labels, :latest_user_content_edit, merge_events: :actor, repository: :owner],
      ))
      .select { |pr| pr.repository&.active? }
      .index_by(&:id)
  end

  def pull_request_reviews_by_id
    @pull_request_reviews_by_id ||= Prelude.wrap(PullRequestReview.where(id: @pull_request_review_ids) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      .includes(pull_request: [
        :user,
        :base_user,
        :head_user,
        repository: :owner,
        review_requests_pending: :reviewer,
        base_repository: [:organization, :owner],
        head_repository: :owner,
        issue: [:labels, :latest_user_content_edit, merge_events: :actor],
      ]))
      .index_by(&:id)
  end

  def pull_request_review_comments_by_id
    @pull_request_review_comments_by_id ||= PullRequestReviewComment.where(id: @pull_request_review_comment_ids)
      .includes(pull_request: [
        :user,
        :base_user,
        :head_user,
        repository: :owner,
        review_requests_pending: :reviewer,
        base_repository: [:organization, :owner],
        head_repository: :owner,
        issue: [:labels, :latest_user_content_edit, merge_events: :actor, repository: :owner],
      ])
      .index_by(&:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  def issue_comments_by_id
    @issue_comments_by_id ||= Prelude.wrap( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      IssueComment
      .includes(
        :user,
        repository: :owner,
        issue: [
          :user,
          :assignees,
          :labels,
          :milestone,
          repository: :owner
        ],
      )
      .where(id: @issue_comment_ids)
    ).index_by(&:id)
  end

  def issues_by_id
    @issues_by_id ||= Prelude.wrap( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        Issue.where(id: @issue_ids)
        .includes(
          :user,
          :assignees,
          :labels,
          :milestone,
          repository: :owner
        )
      )
      .index_by(&:id)
  end

  def tags
    super.concat(["feed_type:api"])
  end
end
