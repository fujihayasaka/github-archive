# typed: strict
# frozen_string_literal: true

# This module defines the interface required to serialize the metadata required to export a set of items
# from the web client into different file formats. Currently the CSV file format is the only format supported by the client,
# nevertheless, this interface can be extended in the future to support other file formats.
#
# Unlike other interfaces under the `MemexProjectColumn` namespace, this interface should NOT be included in
# `MemexProjectColumn` subclasses like `MemexProjectColumn::Field::Base`. Rather it is typically included directly on the
# model that backs the field (e.g. `Issue`, `User`, `MemexProjectColumnValue`, etc).
module MemexProjectColumn::Interface::Serializable
  extend T::Helpers
  interface!

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
