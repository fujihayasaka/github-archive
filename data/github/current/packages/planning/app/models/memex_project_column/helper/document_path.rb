# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Helper::DocumentPath

  # Returns the document path without the optional `keyword` field modifier.
  sig(:final) { params(path: String).returns(String) }
  private def non_keyword_path(path)
    path.gsub(/\.keyword\z/, "")
  end

  # Returns a subpath that we can use directly on a field value document that has been extracted from the
  # overall item document.
  sig(:final) { params(path: String).returns(String) }
  private def field_value_subpath(path)
    # Sorbet doesn't recognize that `self.class.value_name`` exists despite the fact that we've declared
    # `MemexProjectColumn::Field::Base` as a required ancestor. Use `T.unsafe` to work around that.
    unprefixed_path = path.gsub(/\Afield_values\.#{T.unsafe(self).class.value_name}\./, "")

    non_keyword_path(unprefixed_path)
  end
end
