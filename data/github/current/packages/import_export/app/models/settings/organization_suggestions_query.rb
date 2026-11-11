# typed: false
# frozen_string_literal: true

module Settings
  class OrganizationSuggestionsQuery
    class OrganizationSuggestionsQueryFilter < ::Search::Filter
      def global?
        true
      end

      def accessible_organization_ids
        Set.new(Organization.all.pluck(:id))
      end

      def accessible_business_ids
        Set.new([GitHub.global_business.id])
      end
    end

    # Public: Get suggested organizations based on a query and the viewer.
    #
    # query - optional String search query
    # current_user - the currently authenticated User, if any
    # limit - Integer number of results to return at most
    # scope - optional Organization ActiveRecord::Relation to filter returned results
    #
    # Returns an Array of Organization records.
    def self.call(query: nil, current_user: nil, limit: 50, scope: nil)
      limit = 50 if limit > 50 # enforce a maximum cap

      orgs = ::Organization
      orgs = orgs.merge(scope) if scope
      return orgs.by_login.limit(limit).to_a if query.blank?

      search_query = Search::QueryHelper.new(query, "Users",
        current_user: current_user,
        highlight: false,
        page: 1,
        sort: %w(login asc),
        per_page: limit
      )["Users"]
      search_query.filter_hash[:repo_id] = OrganizationSuggestionsQueryFilter.new
      search_results = search_query.execute # array of Search::UserResultView instances
      org_ids = search_results.map { |result| result.id.to_i }

      orgs = orgs.where(id: org_ids).or(orgs.where(login: query))
      exact_matches, fuzzy_matches = orgs.partition { |org| org.display_login.downcase == query.downcase }
      exact_matches + fuzzy_matches
    end
  end
end
