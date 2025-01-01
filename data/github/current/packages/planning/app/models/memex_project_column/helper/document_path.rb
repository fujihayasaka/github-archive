# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Helper::DocumentPath
  extend T::Helpers
  requires_ancestor { MemexProjectColumn::Field::Base }

  # Returns a subpath that we can use directly on a field value document that has been extracted from the
  # overall item document.
  sig(:final) { params(path: String).returns(String) }
  private def field_value_subpath(path) = path.gsub(/\Afield_values\./, "")
end
