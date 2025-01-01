# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module DeleteByQuery
        module Request
          class Params < T::Struct
            # A struct representing all possible parameters that can be passed into the delete_by_query method. Here is an example
            # of default usage:
            #
            #   delete_by_query(Params.new(query: {memex_project_id: 2}, routing: 2))
            #
            # See https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-delete-by-query.html#docs-delete-by-query-api-request-body
            # for reference.
            class Conflicts < T::Enum
              enums do
                Abort = new("abort")
                Proceed = new("proceed")
              end
            end

            class ExpandWildcards < T::Enum
              enums do
                All = new("all")
                Open = new("open")
                Closed = new("closed")
                Hidden = new("hidden")
                None = new("none")
              end
            end

            class DefaultOperator < T::Enum
              enums do
                And = new("AND")
                Or = new("OR")
              end
            end

            class SearchType < T::Enum
              enums do
                QueryThenFetch = new("query_then_fetch")
                DfsQueryThenFetch = new("dfs_query_then_fetch")
              end
            end

            class Refresh < T::Enum
              enums do
                True = new("true")
                False = new("false")
              end
            end

            const :allow_no_indices, T.nilable(T::Boolean)
            const :analyzer, T.nilable(String)
            const :analyze_wildcard, T.nilable(T::Boolean)
            const :conflicts, T.nilable(Conflicts)
            const :default_operator, T.nilable(DefaultOperator)
            const :df, T.nilable(String)
            const :expand_wildcards, T.nilable(ExpandWildcards)
            const :ignore_unavailable, T.nilable(T::Boolean)
            const :lenient, T.nilable(T::Boolean)
            const :max_docs, T.nilable(Integer)
            const :preference, T.nilable(String)
            const :q, T.nilable(String)
            const :request_cache, T.nilable(T::Boolean)
            prop :refresh, T.nilable(Refresh)
            const :requests_per_second, T.nilable(Integer)
            const :routing, T.nilable(Integer)
            const :scroll, T.nilable(String)
            const :scroll_size, T.nilable(Integer)
            const :search_type, T.nilable(SearchType)
            const :search_timeout, T.nilable(String)
            const :slices, T.nilable(Integer)
            const :sort, T.nilable(String)
            const :stats, T.nilable(String)
            const :terminate_after, T.nilable(Integer)
            const :timeout, T.nilable(String)
            const :version, T.nilable(T::Boolean)
            const :wait_for_active_shards, T.nilable(String)

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                allow_no_indices:,
                analyzer:,
                analyze_wildcard:,
                conflicts: conflicts&.serialize,
                default_operator: default_operator&.serialize,
                df:,
                expand_wildcards: expand_wildcards&.serialize,
                ignore_unavailable:,
                lenient:,
                max_docs:,
                preference:,
                q:,
                request_cache:,
                refresh: refresh&.serialize,
                requests_per_second:,
                routing: routing&.to_s,
                scroll:,
                scroll_size:,
                search_type: search_type&.serialize,
                search_timeout:,
                slices:,
                sort:,
                stats:,
                terminate_after:,
                timeout:,
                version:,
                wait_for_active_shards:
              }.compact
            end
          end
        end
      end
    end
  end
end
