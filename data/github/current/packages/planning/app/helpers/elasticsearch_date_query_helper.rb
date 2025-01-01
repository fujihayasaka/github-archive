# typed: strict
# frozen_string_literal: true

module ElasticsearchDateQueryHelper
  include DateMacroHelper

  RangeQuery = Elastomer::Interfaces::Api::Search::Request::RangeQuery

  sig do
    params(
      field_path: String,
      date_value: String,
      context: Search::Memex::Context
    )
    .returns(T.nilable(T::Hash[T.untyped, T.untyped]))
  end
  def date_query(field_path:, date_value:, context:)
    normalized_date_value = replace_today_macro(
      date_value,
      timezone: context.viewer&.time_zone,
      default_time_unit: TimeUnit::Day
    )

    range_query(normalized_date_value, field_path) || match_query(normalized_date_value, field_path)
  end

  sig { params(date_qualifier_value: String).returns(T.nilable(RangeQuery::Operators)) }
  def date_range_clause(date_qualifier_value)
    result = T.let(nil, T.nilable(RangeQuery::Operators))

    range_patterns.each do |pattern, clause_converter|
      if match = date_qualifier_value.match(pattern)
        result = clause_converter.call(match)
        break
      end
    end

    result
  end

  ISO_DATE_REGEX = /\d{4}-[01]\d-[0-3]\d/

  sig do returns(
    T::Hash[
      Regexp,
      T.proc.params(match: MatchData).returns(RangeQuery::Operators)
    ])
  end
  private def range_patterns
    iso_regex = ISO_DATE_REGEX.source
    {
      # Range query, inclusive. For example: 2000-01-01..2000-12-31
      /\A(#{iso_regex})\.\.(#{iso_regex})\z/ => ->(match) { RangeQuery::Operators.new(gte: match[1], lte: match[2]) },
      # Greater than or equal to. For example: >=2000-01-01
      /\A>=(#{iso_regex})\z/                 => ->(match) { RangeQuery::Operators.new(gte: match[1]) },
      # Greater than or equal to, using range syntax. For example: 2000-01-01..*
      /\A(#{iso_regex})\.\.\*\z/             => ->(match) { RangeQuery::Operators.new(gte: match[1]) },
      # Less than or equal to. For example: <=2023-10-26
      /\A<=(#{iso_regex})\z/                 => ->(match) { RangeQuery::Operators.new(lte: match[1]) },
      # Less than or equal to, using range syntax. For example: *..2023-10-26
      /\A\*\.\.(#{iso_regex})\z/             => ->(match) { RangeQuery::Operators.new(lte: match[1]) },
      # Greater than. For example: >1999-12-31
      /\A>(#{iso_regex})\z/                  => ->(match) { RangeQuery::Operators.new(gt: match[1]) },
      # Less than. For example: <2023-10-27
      /\A<(#{iso_regex})\z/                  => ->(match) { RangeQuery::Operators.new(lt: match[1]) },
    }
  end

  sig do
    params(value: String, field_path: String)
    .returns(T.nilable(T::Hash[T.untyped, T.untyped]))
  end
  private def range_query(value, field_path)
    return nil unless date_range_clause = date_range_clause(value)
    RangeQuery.new(field_path:, operators: date_range_clause).to_hash
  end

  sig do
    params(value: String, field_path: String)
    .returns(T.nilable(T::Hash[T.untyped, T.untyped]))
  end
  private def match_query(value, field_path)
    { match: { field_path => value } }
  end
end
