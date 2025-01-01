# typed: strict
# frozen_string_literal: true

# This module defines an interface for models (data sources) to be able to serialize themselves into multiple formats that are necessary
# to be represented as a `MemexProjectColumn` within a `MemexProject`.
#
# This interface currently supports:
#
# - JSON serialization of the value for a field when a `MemexProjectItem` is serialized for the web client
#   (e.g. page load, paginating items, filtering items, creating items, updating items, etc).
# - CSV serialization for when a `MemexProjectItem` is exported as CSV
module MemexProjectColumn::IDataSource
  extend T::Helpers
  abstract!

  delegate :redact!, :redacted?, to: :memex_project_column_value

  # JSONValue represents data that will be serialized as JSON to represent the model on the web client.
  #
  # All keys should be in camelCase format.
  #
  # EXAMPLE:
  #
  #   class UserValue < T::Struct
  #     include MemexProjectColumnValue::SerializableValue
  #
  #     sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  #     def to_hash
  #       {
  #         avatarUrl: primary_avatar_url(40),
  #         id: id,
  #         login: display_login,
  #         url: permalink,
  #       }
  #     end
  #   end
  JSONValue = T.type_alias { T::Hash[T.untyped, T.untyped] }

  # Optional. Returns a MemexProjectColumnValue::* class instance that represents the value of the column.
  #
  # EXAMPLE:
  #
  #   class MemexProjectColumnValue::IssueType < T::Struct
  #     include MemexProjectColumnValue::SerializableValue
  #
  #     def to_hash
  #       {
  #         avatarUrl: primary_avatar_url(40),
  #         id: id,
  #         login: display_login,
  #         url: permalink,
  #       }
  #     end
  #   end
  #
  #   class IssueType
  #     include MemexProjectColumn::IDataSource
  #
  #     sig { override.returns(MemexProjectColumnValue::IssueType) }
  #     def memex_project_column_value
  #       MemexProjectColumnValue::IssueType.new(
  #         id: id,
  #         name: name,
  #         description: description,
  #         color: color.upcase,
  #       )
  #     end
  #   end
  #
  sig { abstract.returns(MemexProjectColumnValue::SerializableValue) }
  def memex_project_column_value; end
end
