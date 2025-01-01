# typed: true
# frozen_string_literal: true

module PullRequest::MemexDependency
  extend T::Helpers
  include MemexProjectItem::Content
  include MemexProjectColumnValue::ReviewerHashable
  include MemexProjectColumn::Interface::Groupable::Metadata
  include MemexProjectColumn::Interface::Sliceable::Metadata
  include MemexProjectColumn::Interface::Serializable

  requires_ancestor { PullRequest }

  def to_issue_authorizable
    T.must(issue).to_issue_authorizable
  end

  def memex_suggestion_hash(last_interaction_at: nil)
    T.must(issue)
      .memex_suggestion_hash(last_interaction_at: last_interaction_at)
      .merge(
        id: id,
        isDraft: draft?,
        state: state.to_s,
        type: "PullRequest",
        updatedAt: updated_at&.utc&.iso8601,
      )
  end

  # Implements MemexProjectItem::Content#memex_content_hash.
  def memex_content_hash(fields: [])
    T.must(issue).memex_content_hash.merge({ id: id })
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def memex_column_hash
    {
      id: id,
      number: number,
      isDraft: draft?,
      state: state.to_s,
      url: url,
    }
  end
  alias_method :group_metadata, :memex_column_hash
  alias_method :slice_metadata, :memex_column_hash

  sig { override.returns(String) }
  def csv_column_value
    url || ""
  end

  # DEPRECATED.
  #
  # This method will be removed over the course of https://github.com/github/i2c-backlog/issues/687.
  # Prefer using `MemexProjectItem#special_type_column_value` directly with the
  # `prefilled_associations` option.
  #
  # Implements MemexProjectItem::Content#memex_special_type_column_value.
  def memex_special_type_column_value(column, require_prefilled_associations: true, redacted_issue_ids: [])
    return [] if column.linked_pull_requests? # pull requests do not have linked pull requests
    return if column.parent_issue? # pull requests do not have parent issues
    return if column.sub_issues_progress? # pull requests do not have sub_issues_progress

    if column.reviewers?
      pull_request_reviewers
    else
      value = T.must(issue).memex_special_type_column_value(
        column,
        require_prefilled_associations: require_prefilled_associations,
        redacted_issue_ids: redacted_issue_ids
      )

      if column.title?
        value[:state] = state.to_s
        value[:isDraft] = draft?
      end

      value
    end
  end

  # Direct use of this method is discouraged!
  # Use `MemexProjectItem#memex_special_type_column_value` instead.
  #
  # This method is used to generate CSV exports for the Memex project board,
  # as part of `MemexProjectItem#memex_special_type_column_value`. which is the reason its direct use is discouraged.
  #
  # Implements MemexProjectItem::Content#memex_special_type_csv_column_value.
  #
  # Returns CSV compatible string
  def memex_special_type_csv_column_value(column, require_prefilled_associations: true, redacted_issue_ids: [])
    return [] if column.linked_pull_requests? # pull requests do not have linked pull requests
    return if column.parent_issue? # pull requests do not have parent issues
    return if column.sub_issues_progress? # pull requests do not have sub_issues_progress

    if column.reviewers?
      pull_request_reviewers.map { |review| review[:reviewer][:login] }.join(", ")
    else
      T.must(issue).memex_special_type_csv_column_value(
        column,
        require_prefilled_associations:,
        redacted_issue_ids:
      )
    end
  end

  # Implements MemexProjectItem::Content#memex_denormalized_title_value.
  def memex_denormalized_title_value
    T.must(issue).memex_denormalized_title_value.merge({
      state: state.to_s,
      isDraft: draft?,
    })
  end

  # Implements MemexProjectItem::Content#can_have_milestone?
  def can_have_milestone?
    true
  end

  # Implements MemexProjectItem::Content#memex_denormalized_milestone_value.
  def memex_denormalized_milestone_value
    milestone&.memex_denormalized_value
  end

  def touch_memex_project_items
    TouchMemexProjectItemsJob.perform_later(self)
  end

  sig { override.returns(Elastomer::Interfaces::Document::MemexProjectItem::Content) }
  def memex_content_elasticsearch_document
    Elastomer::Interfaces::Document::MemexProjectItem::Content.new(
      id: T.must(id),
      type: Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest,
      state: Elastomer::Interfaces::Document::MemexProjectItem::PullRequestState.deserialize(state.to_s),
      state_reason: nil,
      is_draft: draft?,
      number: number,
      repository_id: repository_id,
      user_id: user_id,
      closed_at: closed_at&.iso8601,
      created_at: created_at&.iso8601,
    )
  end

  private def pull_request_reviewers
    pending_requests =
        review_requests
        .select { |r| r.pending? && !r.deferred? && !r.dismissed? } # these are already preloaded so it's more efficient here to filter the array than add a scope.
        .uniq { |r| hashed_reviewer(r.reviewer) }
        .sort_by(&:id)
        .reverse
        .map { |review_request| review_request_hash(review_request) }

    hashed_submitted_requested_users =
      pending_requests
      .map { |r| hashed_reviewer(r) }

    submitted_reviews =
      reviews
      .select(&:submitted?) # these are already preloaded so it's more efficient here to filter the array than add a scope.
      .reject do |r|
        hashed_submitted_requested_users.include?(hashed_reviewer(r.safe_user)) || # exclude reviews submitted by users who have requested a review
        r.safe_user.id == T.must(r.pull_request).user_id || # don't include the author of the pull request
        r.safe_user.ghost? # don't include ghost reviewers (i.e., deleted user accounts)
      end
      .uniq { |r| r.safe_user.id }
      .sort_by { |r| T.must(r.id) }
      .reverse
      .map { |review| pull_request_review_hash(review) }

    submitted_reviews + pending_requests
  end
end
