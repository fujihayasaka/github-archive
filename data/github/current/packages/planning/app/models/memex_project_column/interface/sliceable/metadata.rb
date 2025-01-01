# typed: strict
# frozen_string_literal: true

# This interface contains the methods required to serialize the metadata required to render a slice of items on the
# web client.
#
# Unlike other interfaces under the `MemexProjectColumn` namespace, this interface should NOT be included in
# `MemexProjectColumn` subclasses like `MemexProjectColumn::Field::Base`. Rather it is typically included directly on the
# model that backs the field (e.g. `Issue`, `User`, `MemexProjectColumnValue`, etc).
module MemexProjectColumn::Interface::Sliceable::Metadata
  extend T::Helpers
  abstract!

  sig(:final)  { returns(T.nilable(T::Boolean)) }
  def redact!
    @redacted = T.let(true, T.nilable(T::Boolean))
  end

  sig(:final)  { returns(T::Boolean) }
  def redacted?
    !!@redacted
  end

  sig(:final) { returns(T::Hash[T.untyped, T.untyped]) }
  def to_hash
    redacted? ? redacted_metadata : slice_metadata
  end

  # Returns a hash containing data needed by the web client to render a rich representation of a slice of items.
  #
  # EXAMPLE:
  #
  #   class Label
  #     include MemexProjectColumn::Interface::Sliceable::Metadata
  #
  #     def slice_metadata
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
  private def slice_metadata; end

  sig { overridable.returns(T::Hash[T.untyped, T.untyped]) }
  private def redacted_metadata
    {}
  end
end
