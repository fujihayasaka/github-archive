# typed: strict
# frozen_string_literal: true

# This interface collects all the behaviour needed to query data for a Memex field that is stored in Elasticsearch.
module MemexProjectColumn::Interface::Queryable
  extend T::Helpers
  abstract!

  # This is a sentinel value used to identify an item does not have a value in a particular field.
  # This is useful when we need to expliclity represent that state and it would be confusing to use `nil` to do so.
  MISSING_VALUE_KEY = "_noValue"

  # Utilized by the Search::Memex::Context as a key name for the result
  # of a field query. This method only needs to be defined if the
  # query slug is different than the default `name_slug.to_sym`
  #
  # EXAMPLE
  #  def query_slug
  #    :assignee
  #  end
  sig { abstract.returns(Symbol) }
  def query_slug(); end

  sig do
    abstract
      .params(values: T::Array[String], is_negated: T::Boolean, context: Search::Memex::Context)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def query_fragment(values:, is_negated:, context:); end

  # This hook is used to support the `no:*` qualifier (e.g. `no:assignee`). Consumers should implement this by
  # returning a fragment that queries for the _existence_ of a value in this field.
  #
  # EXAMPLE
  #
  #  def existence_fragment
  #    {
  #      nested: {
  #        path: "field_values",
  #        query: {
  #          exists: {
  #            field: "field_values.assignees_value.login"
  #          }
  #        }
  #      }
  #    }
  #  end
  #
  # @returns A query fragment that can be used to query for values that exist for this field.
  sig { abstract.returns(T::Hash[T.untyped, T.untyped]) }
  def existence_fragment; end

  # Returns a filter for a given field value that is in the same syntax used by our end-users in the Projects filter
  # bar.
  #
  # This is provided as a convenience for extending the query that was actually submitted by an end-user. It is
  # typically used when paginating through the items in a particular group or slice.
  sig(:final) { params(field_value: String).returns(String) }
  def field_value_filter(field_value)
    return "no:#{query_slug}" if field_value == MISSING_VALUE_KEY
    "#{query_slug}:\"#{field_value}\""
  end
end
