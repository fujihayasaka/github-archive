# typed: true
# frozen_string_literal: true

module FilterSuggestions::FilterSuggestionsDependency
  extend T::Helpers
  include GitHub::Memoizer
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
  end

  # Constants to limit overloading the queries with reasonable limits
  MAX_USER_QUERY_COUNT = 100
  MAX_POTENTIAL_ASSIGNABLE_USERS_QUERY_COUNT = 10_000
  MAX_POTENTIAL_ASSIGNEES_PER_SOURCE = 5_000

  # Limit the amount of symbols we query for to reduce abuse possibility.
  MAX_SYMBOL_QUERY_COUNT = 10

  TYPE_AHEAD_RESULT_SIZE = 10
  TOP_REPOSITORIES_SIZE = 2

  MEMEX_PROJECT_CAP_PER_SOURCE = 100

  REPO_QUERY_SYMBOL = :repo
  ORG_QUERY_SYMBOL = :org

  private

  memoize def repositories_from_query
    repo_nwos = values_for_filter(REPO_QUERY_SYMBOL).take(MAX_SYMBOL_QUERY_COUNT)
    repos = Repository.with_names_with_owners(repo_nwos).to_a.compact
    valid_repos = repos.filter { |repo| repo.public? || repo.readable_by?(current_user) }
    cap_filter.authorized_resources(valid_repos)
  end

  def values_for_filter(filter)
    parsed_query.map do |item|
      item.last if item.is_a?(Array) && item.length == 2 && item.first == filter && item.last.is_a?(String)
    end.compact
  end

  memoize def parsed_query
    Search::Queries::IssueQuery.normalize(
      Search::Queries::IssueQuery.parse(params[:q]&.to_s || "", current_user)
    )
  end

  def respond_payload(json)
    respond_to do |format|
      format.json do
        render json: json
      end
    end
  end
end
