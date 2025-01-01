# typed: true
# frozen_string_literal: true

module PullRequest::MemexDependency
  extend T::Helpers
  include MemexProjectItem::Content
  include MemexProjectColumnValue::ReviewerHashable
  include MemexProjectColumn::IDataSource
  include GitHub::Memoizer

  requires_ancestor { PullRequest }

  def to_issue_authorizable
    T.must(issue).to_issue_authorizable # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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

  sig { override.returns(MemexProjectColumnValue::LinkedPullRequest) }
  memoize def memex_project_column_value
    MemexProjectColumnValue::LinkedPullRequest.new(
      id: id,
      number: number,
      is_draft: draft?,
      state: state.to_s,
      url: url,
    )
  end

  # Implements MemexProjectItem::Content#memex_denormalized_title_value.
  sig { returns(MemexProjectColumn::IDataSource::JSONValue) }
  def memex_denormalized_title_value
    T.must(issue).memex_denormalized_title_value.merge({ # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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
    return if repository && ImportExport.domain.is_importing?(T.must(repository))
    TouchMemexProjectItemsJob.perform_later(self)
  end

  sig { override.returns(Elastomer::Interfaces::Document::MemexProjectItem::Content) }
  def memex_content_elasticsearch_document
    Elastomer::Interfaces::Document::MemexProjectItem::Content.new(
      id: T.must(id),
      type: MemexProjectItem::ContentType::PullRequest,
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
end
