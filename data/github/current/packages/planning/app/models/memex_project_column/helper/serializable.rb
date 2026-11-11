# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Helper::Serializable
  extend T::Helpers
  interface!

  # Represents a serializable field value (not backed by a traditional data source)
  #
  # These values are typically constructed from the json_value column the memex_project_column_values table.
  # For example, title is currently represented as:
  #
  # {
  #   "url": "http://github.localhost/5/16/issues/1",
  #   "state": "open",
  #   "title": {
  #     "raw": "issue-type-unset-by-selection0",
  #     "html": "issue-type-unset-by-selection0"
  #   },
  #   "number": 1,
  #   "issueId": 1,
  #   "stateReason": null
  # }
  GenericSerializableValue = T.type_alias do
    T.any(
      T::Array[T::Hash[T.untyped, T.untyped]],
      T::Hash[T.untyped, T.untyped]
    )
  end

  # Represents a serializable field value that can be serialized from a data source. For example,
  # values backed by an ActiveRecord model: Issue, PullRequest, Repository
  DataSourceSerializableValue = T.type_alias do
    T.any(
      T::Array[MemexProjectColumn::IDataSource],
      MemexProjectColumn::IDataSource
    )
  end

  SerializableReturn = T.type_alias do
    T.any(
      DataSourceSerializableValue,
      GenericSerializableValue
    )
  end

  # Returns the backing 'data source' for the field's value, typically an ActiveRecord model for 'special types' or simple hash
  # for 'generic types'.
  #
  # A field may be serialized for use within an internal rest api for rendering a project, for use within the public rest api, or for exporting as CSV.
  #
  # Subclasses are expected to override this method to return an object or array of objects
  # implementing the MemexProjectColumn::IDataSource interface.
  sig do
    abstract.
    params(
      item: MemexProjectItem,
      prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
      redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(SerializableReturn))
  end
  def serializable(item, prefilled_associations: nil, redacted_issue_ids: []); end

end
