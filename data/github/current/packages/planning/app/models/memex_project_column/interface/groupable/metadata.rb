# typed: strict
# frozen_string_literal: true

# This interface contains the methods required to serialize the metadata required to render a set of grouped items
# on the web client.
#
# Unlike other interfaces under the `MemexProjectColumn` namespace, this interface should NOT be included in
# `MemexProjectColumn` subclasses like `MemexProjectColumn::Field::Base`. Rather it is typically included directly on the
# model that backs the field (e.g. `Issue`, `User`, `MemexProjectColumnValue`, etc).
module MemexProjectColumn::Interface::Groupable::Metadata
  extend T::Helpers
  interface!

  # Returns a hash containing data needed by the web client to render a rich representation of a grouped set of
  # items.
  #
  # EXAMPLE:
  #
  #   class Label
  #     include MemexProjectColumn::Interface::Groupable::Metadata
  #
  #     def group_metadata
  #       {
  #         color: color,
  #         id: id,
  #         name: name,
  #         nameHtml: name_html,
  #         url: url,
  #       }
  #     end
  #   end
  #
  sig { abstract.returns(T::Hash[T.untyped, T.untyped]) }
  def group_metadata; end
end
