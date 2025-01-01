# typed: true
# frozen_string_literal: true

module Search
  module Queries
    module CommandPalette
      class RepoQuery < ::Search::Queries::RepoQuery
        # Internal: Returns the Array of field names that will be queried.
        def query_fields
          return @query_fields if defined? @query_fields

          @query_fields = []

          search_in.each do |field|
            case field
            when "name";        @query_fields.concat(%w[name^1.2 name.camel name.ngram^0.8 name_with_owner])
            when "description"; @query_fields << "description"
            when "readme";      @query_fields << "readme"
            end
          end

          if @query_fields.empty?
            @query_fields = %w[name^1.2 name.camel name.ngram^0.8 description^0.5]
            @query_fields << "name_with_owner" if escaped_query.index("/")
          end

          @query_fields
        end

        # Internal: Constructs the actual `:query` portion of the query
        # document. This will later be wrapped in a filtered query if search
        # qualifiers were also used.
        #
        # Returns the search query Hash.
        def query_doc
          query = if escaped_query.present?
            {
              function_score: {
                query: {
                  query_string: {
                    query:            escaped_query,
                    fields:           query_fields,
                    default_operator: "AND",
                  },
                },
                score_mode: "multiply",
                functions: [],
              },
            }
          end

          if filtering_by_topic? || filtering_out_topic? # Searching explicitly for or without an applied topic
            query_with_topics(query)
          else
            query
          end
        end
      end
    end
  end
end
