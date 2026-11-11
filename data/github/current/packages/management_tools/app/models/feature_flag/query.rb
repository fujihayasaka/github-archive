# typed: true
# frozen_string_literal: true

class FeatureFlag::Query
  include GitHub::Memoizer

  DEFAULT_SORT = "last_updated desc"
  QUALIFIERS = %i[
    name
    sort
  ].freeze
  ALLOWED_SORT_KEYS = %w[
    name
    state
    last_updated
  ].freeze

  def initialize(query:, current_user: nil, opts: {})
    @query = query
    @current_user = current_user
    @parsed_query_class = opts[:parsed_query_class] || Search::ParsedQuery
    @search_query_class = opts[:search_query_class] || Search::Query
  end

  def query
    parsed_query.query
  end

  def sort
    return DEFAULT_SORT if invalid_sort?

    search_query.sort
      .each_slice(2)
      .map { _1.join(" ") }
      .join(", ")
  end

  private def invalid_sort?
    return true unless search_query.sort.present?

    search_query.sort.each_slice(2).map(&:first).any? do |sort_value|
      !ALLOWED_SORT_KEYS.include?(sort_value)
    end
  end

  private

  memoize def parsed_query
    @parsed_query_class.new(@query, QUALIFIERS, @current_user)
  end

  # I have no idea yet why passing in the qualifiers to the initializer is not
  # working so instead we'll #tap
  memoize def search_query
    @search_query_class.new(phrase: parsed_query.phrase).tap do |query|
      query.qualifiers = parsed_query.qualifiers
    end
  end
end
