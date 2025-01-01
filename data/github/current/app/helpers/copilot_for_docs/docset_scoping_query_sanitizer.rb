# typed: true
# frozen_string_literal: true

module CopilotForDocs

  # Scrubs out repos the user isn't allowed to view
  class DocsetScopingQuerySanitizer
    include GitHub::Memoizer

    attr_reader :query


    # given a docset, parse the scoping query for "repo:owner/name" tokens and remove any
    # "repo:owner/can-view OR repo:owner/cannot-view OR repo:owner/can-also-view" becomes "repo:owner/can-view OR repo:owner/can-also-view"
    # that the user is not authorized to view. Mutates the given docset
    def self.remove_unviewable_scoping_query_repos(docset, cap_filter, current_user)
      key = docset[:scopingQuery] ? :scopingQuery : "scopingQuery"
      sanitizer = new(query: docset[key])
      repos_in_scoping_query = Repository.with_names_with_owners(sanitizer.repo_nwos)

      authorized_repos = repos_in_scoping_query.reject { |repo| !repo.readable_by?(current_user) || !cap_filter.unauthorized([repo]).empty? }
      authorized_nwos = authorized_repos.map(&:name_with_display_owner)

      docset[key] = sanitizer.filtered_scoping_query(authorized_nwos)

      docset
    end

    def initialize(query:)
      @query = query
    end

    def filtered_scoping_query(allowed_nwos)
      query_scopes.filter do |scope|
        allowed_nwos.include?(repo_nwo(scope))
      end.join(" OR ")
    end

    def repo_nwos
      query_scopes.map { |scope| repo_nwo(scope) }
    end

    private

    def repo_nwo(scope)
      scope[/repo:([^\/\s][\w\-\/\.\_]+)/, 1]
    end

    memoize def query_scopes
      # if the query has no OR clause and has both a repo: and path:, return an array
      # of just one element containing the whole query
      if !query.include?(" OR ") && query.match(/\Arepo:[^\s]+/)
        [query]
      else
        query.scan(/(?<= OR |^)\(.*?\)(?= OR |$)|(?<= OR |^)repo:[^\s]+(?= OR |$)/)
      end
    end
  end
end
