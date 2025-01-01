# typed: strict
# frozen_string_literal: true

# This interface collects all the behaviour needed to query data for a Memex field that is stored in Elasticsearch.
module MemexProjectColumn::Interface::Queryable
  extend T::Helpers
  abstract!

  # This is a sentinel value used to identify an item does not have a value in a particular field.
  # This is useful when we need to expliclity represent that state and it would be confusing to use `nil` to do so.
  MISSING_VALUE_KEY = "_noValue"
  RangeQuery = Elastomer::Interfaces::Api::Search::Request::RangeQuery
  MatchQuery = Elastomer::Interfaces::Api::Search::Request::MatchQuery

  requires_ancestor { MemexProjectColumn::Field::Base }

  module ClassMethods
    extend T::Helpers
    abstract!

    # Fields that are queryable must override this method to return true.
    sig { abstract.returns(T::Boolean) }
    def queryable?; end
  end

  mixes_in_class_methods(ClassMethods)

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

  # The path to the field that defines the queryable value in the Elasticsearch document for this field type.
  sig { abstract.returns(String) }
  def query_by_value_path; end

  # The mapping strategy for finding field documents matching the given value.
  #
  # This method should return a hash representing an Elasticsearch TermQuery, RangeQuery, or similar.
  sig do
    abstract
    .params(value: String, context: Search::Memex::Context)
    .returns(T.nilable(T::Hash[T.untyped, T.untyped]))
  end
  def query_strategy(value:, context:); end

  sig(:final) do
    params(values: T::Array[String], is_negated: T::Boolean, context: Search::Memex::Context)
    .returns(T::Hash[T.untyped, T.untyped])
  end
  def query_fragment(values:, is_negated:, context:)
    should_clauses = values.map do |value|
      strategy = query_strategy(value:, context:)
      next unless strategy.present?

      # For generically-typed fields, there can be multiple instances of the same field in a given project (e.g. two
      # different single-select fields). Hence we must add an additional clause that filters down to the correct field.
      if generic_type?
        strategy = {
          bool: {
            must: [
              {
                term: {
                  "field_values.field_id": { value: id },
                }
              },
              strategy
            ]
          }
        }
      end

      {
        nested: {
          path: "field_values",
          query: strategy,
        }
      }
    end

    wrap_query_fragment(should_clauses:, is_negated:)
  end

  sig { params(value: String).returns(MatchQuery) }
  private def match_query(value)
    MatchQuery.new(
      field_path: query_by_value_path,
      value:
    )
  end

  sig do returns(
    T::Hash[
      Regexp,
      T.proc.params(match: MatchData).returns(RangeQuery::Operators)
    ])
  end
  private def range_patterns
    {
      # Range query, inclusive. For example: 1..10
      /\A(\d+)\.\.(\d+)\z/ => ->(match) { RangeQuery::Operators.new(gte: match[1], lte: match[2]) },
      # Greater than or equal to. For example: >=1
      /\A>=(\d+)\z/        => ->(match) { RangeQuery::Operators.new(gte: match[1]) },
      # Greater than or equal to, using range syntax. For example: 10..*
      /\A(\d+)\.\.\*\z/    => ->(match) { RangeQuery::Operators.new(gte: match[1]) },
      # Less than or equal to. For example: <=10
      /\A<=(\d+)\z/        => ->(match) { RangeQuery::Operators.new(lte: match[1]) },
      # Less than or equal to, using range syntax. For example: *..10
      /\A\*\.\.(\d+)\z/    => ->(match) { RangeQuery::Operators.new(lte: match[1]) },
      # Greater than. For example: >1
      /\A>(\d+)\z/         => ->(match) { RangeQuery::Operators.new(gt: match[1]) },
      # Less than. For example: <10
      /\A<(\d+)\z/         => ->(match) { RangeQuery::Operators.new(lt: match[1]) },
    }
  end

  sig { params(value: String).returns(T.nilable(RangeQuery)) }
  private def range_query(value)
    range_clause = range_patterns.filter_map do |pattern, clause_converter|
      if match = value.match(pattern)
        clause_converter.call(match)
      end
    end

    return nil if range_clause.empty?

    RangeQuery.new(
      field_path: query_by_value_path,
      operators: T.must(range_clause.first)
    )
  end

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


  # Provides a consistent 'bool' wrapper around the field's optionally negated query_fragment
  sig(:final) do params(should_clauses: T::Array[T.nilable(T::Hash[T.untyped, T.untyped])], is_negated: T::Boolean)
    .returns(T::Hash[T.untyped, T.untyped])
  end
  private def wrap_query_fragment(should_clauses:, is_negated:)
    inner_bool_clause = if is_negated
      { must_not: should_clauses.compact }
    else
      # 'minimum_should_match' defaults to 1 in this context anyway,
      # but just being explicit that only 1 'should' term is required to match.
      { should: should_clauses.compact, minimum_should_match: 1 }
    end
    {
      bool: inner_bool_clause
    }
  end
end
