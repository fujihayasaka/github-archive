# typed: strict
# frozen_string_literal: true

# Shared helper for computing dynamic issue index cache TTLs.
# Used by IssuesReactHelper (initial page load) and InternalGraphqlController (revalidation).
module IssuesCacheTtlHelper
  # Qualifiers that appear in the default (unfiltered) issue index query.
  # Any query containing only these qualifiers is considered a "default" query.
  ISSUE_INDEX_DEFAULT_QUALIFIERS = T.let(Set.new(%w[is state repo sort archived type]).freeze, T::Set[String])

  # Computes a server-driven cache TTL (in milliseconds) for the issue index page based on
  # recent issue creation activity in the repository. The result is cached in Rails.cache for
  # 1 hour to avoid repeated DB reads.
  #
  # repository - The Repository record to compute the TTL for.
  #
  # Returns an Integer TTL in milliseconds.
  sig { params(repository: Repository).returns(Integer) }
  def compute_issue_index_cache_ttl(repository)
    Rails.cache.fetch("issue_index_cache_ttl:repo:#{repository.id}", expires_in: 1.hour) do
      from_date = 7.days.ago.to_date
      weekly_issues = CommunityInsightsDailyCount
        .where(repository_id: repository.id, entry_date: from_date..Date.today)
        .sum(:issues_count)
      daily_avg = weekly_issues / 7.0

      case daily_avg
      when 0..1    then 7.days.in_milliseconds.to_i
      when 1..5    then 1.day.in_milliseconds.to_i
      when 5..20   then 12.hours.in_milliseconds.to_i
      when 20..100 then 2.hours.in_milliseconds.to_i
      else              30.minutes.in_milliseconds.to_i
      end
    end
  end

  # Returns true when the query string contains only the standard qualifiers
  # present in an unfiltered issue index view (e.g. "is:issue state:open repo:owner/name sort:created-desc").
  # Free-text search terms or additional filter qualifiers (label:, assignee:, etc.) return false.
  sig { params(query_string: T.nilable(String)).returns(T::Boolean) }
  def default_issue_index_query?(query_string)
    return false if query_string.blank?

    tokens = query_string.strip.split(/\s+/)
    tokens.all? do |token|
      colon_idx = token.index(":")
      colon_idx && ISSUE_INDEX_DEFAULT_QUALIFIERS.include?(T.must(token[0...colon_idx]))
    end
  end

  # Injects a `serverCacheTTL` key into the GraphQL result hash for the IssueIndexPageQuery
  # when the query is a default (unfiltered) view.
  # Both the SSR query preloader and the internal GraphQL controller use this so the client
  # always receives the TTL in the response payload rather than via a response header.
  sig { params(result_hash: T::Hash[T.any(String, Symbol), T.untyped], query_id: T.nilable(String), variables: T.nilable(T::Hash[String, T.untyped])).void }
  def maybe_inject_issue_index_cache_ttl(result_hash, query_id, variables)
    return unless query_id == IssuesReactGraphqlQueries::ISSUE_INDEX_PAGE_QUERY.graphql_query_id
    return unless default_issue_index_query?(variables&.dig("query"))

    owner = variables&.dig("owner")
    name = variables&.dig("name")
    return unless owner.present? && name.present?

    repository = Repository.nwo(owner, name)
    return unless repository

    result_hash["serverCacheTTL"] = compute_issue_index_cache_ttl(repository)
  end
end
