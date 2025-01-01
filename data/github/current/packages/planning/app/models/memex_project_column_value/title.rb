# typed: strict
# frozen_string_literal: true

# `MemexProjectItem::Title` is a wrapper for the title of a `MemexProjectItem` within a `MemexProject`.
#
# `MemexProjectItem::Title` can be initialized with a denormalized title value directly from `MemexProjectColumnValue`
# where the hash will contain string keys, or it can be initialized directly from the underlying content model's
# `memex_denormalized_title_value` method. See `Issue#memex_denormalized_title_value` as an example.
class MemexProjectColumnValue::Title < T::Struct
  include MemexProjectColumnValue::SerializableValue

  const :raw_title, String
  const :html_title, String
  const :number, T.nilable(Integer)
  const :url, T.nilable(String)
  const :issue_id, T.nilable(Integer)
  const :state, T.nilable(String)
  const :state_reason, T.nilable(String)
  const :is_draft, T.nilable(T::Boolean)

  # When the item is a draft issue only [:title] should be returned.
  # When the item is an issue [:title, :number, :issueId, :state, :url, :stateReason] should be returned.
  # When the item is a pull request [:title, :number, :issueId, :state, :url, :isDraft] should be returned.
  # This is based on the implementation of `memex_denormalized_title_value` in those models.
  sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_hash
    {
      title: {
        raw: raw_title,
        html: html_title,
      },
    }.tap do |hash|
      hash[:number] = number unless number.nil?
      hash[:issueId] = issue_id unless issue_id.nil?
      hash[:state] = state unless state.nil?
      hash[:url] = url unless url.nil?
      # stateReason should be included only if it's an issue
      hash[:stateReason] = state_reason if !issue_id.nil? && is_draft.nil?
      hash[:isDraft] = is_draft unless is_draft.nil?
    end
  end

  sig { override.returns(String) }
  def to_s
    html_title
  end

  sig { override.returns(String) }
  def to_csv
    raw_title
  end
end
