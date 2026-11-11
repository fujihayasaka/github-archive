# typed: strict
# frozen_string_literal: true

# This class uses the redactor functionality. `to_redacted_hash` must be implemented. Other serialization methods
# that get added should also consider redaction and use `redacted?` to modify their return values accordingly.
#
class MemexProjectColumnValue::ParentIssue < T::Struct
  include MemexProjectColumnValue::SerializableValue

  REDACTED_ISSUE_TITLE = "You can't see this issue"

  const :id, Integer
  const :global_relay_id, String
  const :number, Integer
  const :state, String
  const :state_reason, String
  const :title, String
  const :title_html, String
  const :title_with_nwo, String
  const :repository_name, T.nilable(String)
  const :repository_owner, T.nilable(String)
  const :repository_id, Integer
  const :nwo_reference, String
  const :url, String
  const :sub_issue_list, T.nilable(MemexProjectColumnValue::SubIssuesProgress)
  const :updated_at, String
  const :permalink, String
  const :blocked_by_count, Integer

  sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_hash
    {
      id: id,
      globalRelayId: global_relay_id,
      number: number,
      state: state,
      stateReason: state_reason,
      title: title,
      titleHtml: title_html,
      titleWithNwo: title_with_nwo,
      repository: repository_name,
      owner: repository_owner,
      nwoReference: nwo_reference,
      url: url,
      subIssueList: sub_issue_list&.to_hash,
      updatedAt: updated_at,
      blockedByCount: blocked_by_count,
    }
  end

  sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_redacted_hash
    {
      id: id,
      globalRelayId: global_relay_id,
      number: number,
      state: nil,
      stateReason: nil,
      title: REDACTED_ISSUE_TITLE,
      titleHtml: REDACTED_ISSUE_TITLE,
      repository: nil,
      owner: nil,
      nwoReference: "#{repository_id}##{number}",
      url: nil,
      subIssueList: nil,
      updatedAt: nil,
    }
  end

  sig { override.returns(String) }
  def to_s
    redacted? ? REDACTED_ISSUE_TITLE : title_with_nwo
  end

  sig { override.returns(String) }
  def to_csv
    permalink.to_s
  end
end
