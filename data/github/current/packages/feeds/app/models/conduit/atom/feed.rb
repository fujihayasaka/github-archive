# typed: true
# frozen_string_literal: true

class Conduit::Atom::Feed < Conduit::Feed
  include GitHub::Memoizer

  def after_build
    GitHub.dogstats.distribution_time("conduit.preload_feed", tags:) do
      preload_labels
    end
  end

  memoize def pull_requests_by_id
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

  memoize def issues_by_id
    Prelude.wrap(Issue.where(id: @issue_ids) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      .includes(
        :user,
        :repository,
        :labels,
        :pull_request,
        repository: :owner
      ))
      .index_by(&:id)
  end

  private

  def preload_labels
    label_ids = issue_label_ids + pull_request_label_ids

    cached_records[:labels] ||= Label.where(id: label_ids)
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

  def tags
    super.concat(["feed_type:atom"])
  end
end
