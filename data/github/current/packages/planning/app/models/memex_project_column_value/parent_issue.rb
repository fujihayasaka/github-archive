# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::ParentIssue < T::Struct
  const :id, Integer
  const :global_relay_id, String
  const :number, Integer
  const :state, String
  const :state_reason, String
  const :title, String
  const :title_html, String
  const :repository_name, T.nilable(String)
  const :repository_owner, T.nilable(String)
  const :nwo_reference, String
  const :url, String
  const :sub_issue_list, T.nilable(SubIssueList)
  const :updated_at, String
  const :permalink, String
  const :blocked_by_count, Integer

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def to_hash
    {
      id: id,
      globalRelayId: global_relay_id,
      number: number,
      state: state,
      stateReason: state_reason,
      title: title,
      titleHtml: title_html,
      repository: repository_name,
      owner: repository_owner,
      nwoReference: nwo_reference,
      url: url,
      subIssueList: sub_issue_list&.memex_column_hash,
      updatedAt: updated_at,
      blockedByCount: blocked_by_count,
    }
  end

  sig { returns(String) }
  def to_csv
    permalink
  end
end
