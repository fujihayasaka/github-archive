# typed: true
# frozen_string_literal: true

class Conduit::Api::Feed < Conduit::Feed
  include GitHub::Memoizer

  def after_build
    GitHub.dogstats.distribution_time("conduit.preload_feed", tags:) do
      preload_labels
      preload_assignees
      preload_pull_requests
      preload_releases
    end
    super
  end

  memoize def pull_requests_by_id
    track_preload_metrics(:pull_requests) do
      if minimized_payload?
        Prelude.wrap(PullRequest.where(id: @pull_request_ids) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          .includes(
            :issue,
            repository: :owner,
            base_repository: :owner,
            head_repository: :owner,
          ))
          .select { |pr| pr.repository&.active? }
          .index_by(&:id)
      else
        Prelude.wrap(PullRequest.where(id: @pull_request_ids) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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
    end
  end

  memoize def issues_by_id
    track_preload_metrics(:issues) do
      Prelude.wrap( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          Issue.where(id: @issue_ids)
          .includes(
            :user,
            :assignee,
            :assignees,
            :labels,
            :pull_request,
            :reactions,
            milestone: :created_by,
            performed_via_integration: [
              :owner,
              latest_version: [:default_event_records, :default_permission_records],
            ],
            repository: :owner
          )
        )
        .index_by(&:id)
    end
  end

  private

  def preload_pull_requests
    return if minimized_payload?

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

  def preload_releases
    releases = releases_by_id.values

    GitHub::PrefillAssociations.prefill_batch_method(
      releases,
      :mentions_count,
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

  memoize def discussions_by_id
    track_preload_metrics(:discussions) do
      Discussion.where(id: @discussion_ids)
        .includes(
          :category,
          :chosen_comment,
          :comments,
          :labels,
          :reactions,
          :user,
          repository: :owner
        )
        .filter { |d| d.body.present? }
        .index_by(&:id)
    end
  end

  memoize def releases_by_id
    track_preload_metrics(:releases) do
      relationships = {
        author: {},
        uploaded_assets: {},
        reactions: {},
        discussion: { repository: :owner },
        repository: :owner,
      }

      Releases::Public.load_releases(@release_ids.to_a, relationships: relationships)
        .index_by(&:id)
    end
  end

  def pull_request_comments_by_id
    track_preload_metrics(:pull_request_comments) do
      @pull_request_comments_by_id ||= IssueComment
        .with_pull_request
        .includes(
          :user,
          :reactions,
          repository: :owner,
          issue: [:pull_request, :repository],
        )
        .where(id: @pull_request_comment_ids)
        .index_by(&:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end

  def issue_comments_by_id
    track_preload_metrics(:issue_comments) do
      @issue_comments_by_id ||= Prelude.wrap( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        IssueComment
        .includes(
          :user,
          :reactions,
          repository: :owner,
          issue: :repository,
          performed_via_integration: [
            :owner,
            latest_version: [:default_event_records, :default_permission_records],
          ],
        )
        .where(id: @issue_comment_ids)
      ).index_by(&:id)
    end
  end

  def pull_request_reviews_by_id
    track_preload_metrics(:pull_request_reviews) do
      @pull_request_reviews_by_id ||= PullRequestReview.where(id: @pull_request_review_ids)
        .includes(:user, pull_request: :issue)
        .index_by(&:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end

  memoize def pull_request_review_comments_by_id
    track_preload_metrics(:pull_request_review_comments) do
      PullRequestReviewComment.where(id: @pull_request_review_comment_ids)
        .includes(:reactions, :user, pull_request: [:repository, :issue])
        .index_by(&:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end

  def tags
    super.concat(["feed_type:api"])
  end
end
