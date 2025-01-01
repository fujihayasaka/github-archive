# typed: strict
# frozen_string_literal: true

# This interface collects all the behaviour needed to sort data for a Memex field that is stored in Elasticsearch.
#
# Provides an interface for generating a sort fragment to when executing an Elasticsearch query.
# This is used to sort MemexProjectItems by a given field.
#
# This interface is intended to be included in MemexProjectColumn::Field::Base.
#
# USAGE:
#
#   include Sortable
#
#   sig do
#     override
#       .params(direction: String)
#       .returns(T::Hash[T.untyped, T.untyped])
#   end

#   def sort_fragment(direction:)
#     {
#       "field_values.#{self.class.value_name}": {
#         order: direction,
#         nested_path: "field_values",
#         nested_filter: {
#           bool: {
#             must: [
#               {
#                 term: {
#                   "field_values.field_id": { value: id }
#                 }
#               }
#             ]
#          }
#        }
#      }
#   }
# end

module MemexProjectColumn::Interface::Sortable
  extend T::Helpers
  interface!

  Params = T.type_alias { T::Array[Param] }

  MAX_64_BIT_SIGNED_INTEGER = 9223372036854775807
  private_constant :MAX_64_BIT_SIGNED_INTEGER

  MIN_64_BIT_SIGNED_INTEGER = -9223372036854775808
  private_constant :MIN_64_BIT_SIGNED_INTEGER

  # Returns an Elasticsearch sort fragment for a given sort direction for a field.
  #
  # Returns a valid JSON fragment that can be used as sort parameter of an Elasticsearch query and passed as the `sort` argument to MemexProjectItemQuery.
  # See https://www.elastic.co/guide/en/elasticsearch/reference/current/sort-search-results.html for further documentation on constructing Elastcisearch sort fragments.
  #
  # USAGE:
  #
  #   memex_project_column.to_field.sort_fragment(direction: "asc")
  #
  # @param <direction> Direction to sort by.
  sig do
    abstract
      .params(direction: String)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def sort_fragment(direction:); end
end
