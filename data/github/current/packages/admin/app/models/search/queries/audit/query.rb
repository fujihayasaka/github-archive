# typed: true
# frozen_string_literal: true

module Search
  module Queries
    module Audit
      class Query < ::Search::Query
        # Set number of hits returned per page.
        def self.per_page_default
          50
        end

        # Set max offset of audit log entries user can query.
        def self.max_offset_default
          15_000
        end

        # Querying across all audit log indexes takes longer than 250ms.
        QUERY_TIMEOUT = "1000ms".freeze

        def initialize(options = {}, &block)
          @index = Elastomer::Indexes::AuditLog.new(options.delete(:index_name))

          super(options, &block)
        end

        def build_query
          # build query & filter subtrees
          qd = query_doc || { match_all: {} }
          filter = build_query_filter

          # build parent clause (to be nested in top-level "query" clause)
          bool_q = { bool: { must: qd } }
          bool_q[:bool][:filter] = filter if filter

          bool_q
        end

        def normalize(results)
          results.map! do |hit|
            hit = ::Audit::Elastic::Hit.new(hit)
            hit.after_initialize
            hit
          end
        end

        def build_sort
          {
            :@timestamp => {
              order: :desc,
            },
          }
        end
      end
    end
  end
end
