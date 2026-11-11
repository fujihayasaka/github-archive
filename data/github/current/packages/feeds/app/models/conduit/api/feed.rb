# typed: true
# frozen_string_literal: true

class Conduit::Api::Feed < Conduit::Feed
  include GitHub::Memoizer

  def after_build
    preload_labels
    preload_assignees
    preload_releases
    preload_reaction_counts
    super
  end

  memoize def pull_requests_by_id
    track_preload_metrics(:pull_requests) do
      Prelude.wrap(PullRequest.where(id: @pull_request_ids) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        .includes(
          :issue,
          repository: :owner,
          base_repository: :owner,
          head_repository: :owner,
        ))
        .select { |pr| pr.repository&.active? }
        .index_by(&:id)
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
            :issue_dependency_list,
            :labels,
            :parent_issue_relation,
            :pull_request,
            :reactions,
            :sub_issue_list,
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

  def preload_releases
    releases = releases_by_id.values

    GitHub::PrefillAssociations.prefill_batch_method(
      releases,
      :mentions_count,
    )

    GitHub::PrefillAssociations.prefill_batch_method(
      releases,
      :short_description_info,
      {}
    )
  end

  def preload_reaction_counts
    # Prefill reaction counts for all reactable items to avoid N+1 queries
    all_reactable_items = []

    all_reactable_items.concat(releases_by_id.values)
    all_reactable_items.concat(discussions_by_id.values)
    all_reactable_items.concat(issues_by_id.values)
    all_reactable_items.concat(issue_comments_by_id.values)
    all_reactable_items.concat(pull_request_comments_by_id.values)
    all_reactable_items.concat(pull_request_review_comments_by_id.values)
    all_reactable_items.concat(commit_comments_by_id.values)

    Reaction::Summary.prefill(all_reactable_items) if all_reactable_items.any?
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
          :chosen_comment,
          :comments,
          :labels,
          :reactions,
          :user,
          category: :repository,
          repository: [:organization_discussion, :owner],
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

  memoize def pull_request_comments_by_id
    track_preload_metrics(:pull_request_comments) do
      IssueComment
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

  memoize def issue_comments_by_id
    track_preload_metrics(:issue_comments) do
      Prelude.wrap( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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

  memoize def pull_request_reviews_by_id
    track_preload_metrics(:pull_request_reviews) do
      PullRequestReview.where(id: @pull_request_review_ids)
        .includes(:user, pull_request: :issue)
        .index_by(&:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end

  memoize def pull_request_review_comments_by_id
    track_preload_metrics(:pull_request_review_comments) do
      PullRequestReviewComment.where(id: @pull_request_review_comment_ids)
        .includes(
          :pull_request_review_thread,
          :reactions,
          :user,
          pull_request: [:repository, :issue],
        )
        .index_by(&:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end

  memoize def repositories_by_id
    track_preload_metrics(:repositories) do
      Repositories::Public.load_repositories(@repository_ids.to_a)
        .includes(:network, :owner, :primary_language, :parent)
        .index_by(&:id)
    end
  end

  def tags
    super.concat(["feed_type:api"])
  end
end
