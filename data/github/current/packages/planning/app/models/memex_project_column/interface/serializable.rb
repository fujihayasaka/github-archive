# typed: strict
# frozen_string_literal: true

# This module defines an interface for models to be able to serialize itself in multiple formats that are necessary
# to be represented as a `MemexProjectColumn` within a `MemexProject`.
#
# This interface currently supports:
#
# - JSON serialization of the value for a field when a `MemexProjectItem` is serialized for the web client
#   (e.g. page load, paginating items, filtering items, creating items, updating items, etc).
# - CSV serialization for when a `MemexProjectItem` is exported as CSV
#
# Unlike other interfaces under the `MemexProjectColumn` namespace, this interface should NOT be included in
# `MemexProjectColumn` subclasses like `MemexProjectColumn::Field::Base`. Rather it is typically included directly on the
# model that backs the field (e.g. `Issue`, `User`, `MemexProjectColumnValue`, etc).
module MemexProjectColumn::Interface::Serializable
  extend T::Helpers
  interface!

  # JSONValue represents data that will be serialized as JSON to represent the model on the web client.
  #
  # All keys should be in camelCase format.
  #
  # EXAMPLE:
  #
  #   class User
  #     include MemexProjectColumn::Interface::Serializable
  #
  #     sig { override.returns(MemexProjectColumn::Interface::Serializable::JSONValue) }
  #     def memex_column_hash
  #       {
  #         avatarUrl: primary_avatar_url(40),
  #         id: id,
  #         login: display_login,
  #         url: permalink,
  #       }
  #     end
  #   end
  JSONValue = T.type_alias { T::Hash[T.untyped, T.untyped] }

  # Returns a JSONValue containing the data that will be serialized as JSON to represent the model on the web client.
  # All keys should be in camelCase format.
  #
  # EXAMPLE:
  #
  #   class User
  #     include MemexProjectColumn::Interface::Serializable
  #
  #     sig { override.returns(MemexProjectColumn::Interface::Serializable::JSONValue) }
  #     def memex_column_hash
  #       {
  #         avatarUrl: primary_avatar_url(40),
  #         id: id,
  #         login: display_login,
  #         url: permalink,
  #       }
  #     end
  #   end
  #
  sig { abstract.returns(MemexProjectColumn::Interface::Serializable::JSONValue) }
  def memex_column_hash; end

  # Returns a CSV compatible string containing data needed by the web export to render a rich representation of a column value.
  #
  # EXAMPLE:
  #
  #   class Label
  #     include MemexProjectColumn::Interface::Serializable
  #
  #     sig { override.returns(String) }
  #     def csv_column_value
  #       name || ""
  #     end
  #   end
  #
  sig { abstract.returns(String) }
  def csv_column_value; end
end
