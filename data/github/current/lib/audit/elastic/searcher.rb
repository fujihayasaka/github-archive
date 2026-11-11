# typed: true
# frozen_string_literal: true

module Audit
  module Elastic
    # Queries ElasticSearch for audit logs.
    class Searcher < Adapter
      # Internal: Queries ElasticSearch.
      #
      # options - A Hash of options to build the query.
      #
      # Returns Search::Results instance.
      def perform(options)
        query_options = options.merge(index_name: Rails.env.test? && generate_index)
        query = Search::Queries::AuditLogQuery.new(query_options)

        begin
          query.execute
        rescue StandardError => boom # rubocop:todo Lint/RescueException
          Failbot.report(boom, options: options, fatal: "NO")
          Search::Results.empty
        end
      end
    end
  end
end
