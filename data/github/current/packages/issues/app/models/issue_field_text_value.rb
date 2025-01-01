# typed: strict
# frozen_string_literal: true

class IssueFieldTextValue < IssueFieldValue
  include Issues::IIssueFieldTextValue
  include MemexProjectColumn::IDataSource
  include GitHub::Memoizer

  sig { returns(String) }
  def self.sti_name
    "text"
  end

  # Returns the raw value for text fields
  sig { override.returns(String) }
  def value
    raw_value
  end

  # Returns the lowercase text value for ElasticSearch indexing
  sig { override.returns(T.nilable(String)) }
  def elasticsearch_value
    return nil unless value.present?
    value.downcase
  end

  sig { override.returns(MemexProjectColumnValue::Text) }
  memoize def memex_project_column_value
    MemexProjectColumnValue::Text.new(value:)
  end
end
