# typed: true
# frozen_string_literal: true

class FeatureFlag::Query
  include GitHub::Memoizer

  DEFAULT_SORT = "rollout_updated_at desc"
  QUALIFIERS = %i[
    starts
    ends
    service
    sort
  ].freeze
  ALLOWED_SORT_KEYS = %w[
    rollout_updated_at
    rollout
    created_at
    updated_at
    name
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
      .gsub(/rollout\b/, "rollout_updated_at") # allow users to pass in "rollout" instead of "rollout_updated_at"
  end

  private def invalid_sort?
    return true unless search_query.sort.present?

    search_query.sort.each_slice(2).map(&:first).any? do |sort_value|
      !ALLOWED_SORT_KEYS.include?(sort_value)
    end
  end

  def service
    return unless parsed_query.qualifiers[:service]&.must

    parsed_query.qualifiers[:service].must.join(",")
  end

  def starts
    parsed_query.qualifiers[:starts]&.must&.first
  end

  def ends
    parsed_query.qualifiers[:ends]&.must&.first
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
