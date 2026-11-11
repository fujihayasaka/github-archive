# typed: strict
# frozen_string_literal: true

module Search
  module Helpers
    module ListHelper
      sig { params(query: T.nilable(String), user: T.nilable(User), page: String).void }
      def self.instrument_query_terms(query, user, page)
        return if query.blank?

        parsed = ::Search::Queries::RepoQuery.coerce(query.downcase, user)

        raw_term = T.let(false, T::Boolean)
        props    = T.let(false, T::Boolean)
        terms    = []

        parsed.each do |component|
          if component.is_a?(String)
            raw_term = true
            next
          end

          key, = component
          if key.to_s.start_with?("props.")
            props = true
          else
            terms << key.to_s
          end
        end

        GitHub.dogstats.increment("repos_list.query_terms", tags: ["page:#{page}", "term:_raw"]) if raw_term
        GitHub.dogstats.increment("repos_list.query_terms", tags: ["page:#{page}", "term:_props"]) if props
        terms.each do |term|
          GitHub.dogstats.increment("repos_list.query_terms", tags: ["page:#{page}", "term:#{term}"])
        end
      end
    end
  end
end
