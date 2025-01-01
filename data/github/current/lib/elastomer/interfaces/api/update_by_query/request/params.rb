# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module UpdateByQuery
        module Request
          # A struct representing all possible parameters that can be passed into the update_by_query method. Here is an example
          # of default usage:
          #
          # update_by_query(<Body>, Params.new(id: 1, routing: 2))
          #
          # See https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-update-by-query.html#docs-update-by-query-api-query-params for reference
          class Params < T::Struct
            extend T::Sig

            class Conflicts < T::Enum
              enums do
                Abort = new("abort")
                Proceed = new("proceed")
              end
            end

            class DefaultOperator < T::Enum
              enums do
                AND = new("AND")
                OR = new("OR")
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

            class SearchType < T::Enum
              enums do
                QueryThenFetch = new("query_then_fetch")
                DfsQueryThenFetch = new("dfs_query_then_fetch")
              end
            end

            # See https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-refresh.html for reference
            class Refresh < T::Enum
              enums do
                True = new("true")
                False = new("false")
              end
            end

            # Optional

            prop :analyzer, T.nilable(String)
            prop :conflicts, T.nilable(Conflicts)
            prop :df, T.nilable(String)
            prop :max_docs, T.nilable(Integer)
            prop :pipeline, T.nilable(String)
            prop :preference, T.nilable(String)
            prop :q, T.nilable(String)
            prop :request_cache, T.nilable(T::Boolean)
            prop :request_per_second, T.nilable(Integer)
            prop :routing, T.nilable(T.any(Integer, String))
            prop :search_type, T.nilable(SearchType)
            prop :slices, T.nilable(Integer)
            prop :sort, T.nilable(String)
            prop :stats, T.nilable(String)
            prop :terminate_after, T.nilable(Integer)
            prop :version, T.nilable(T::Boolean)
            prop :wait_for_active_shards, T.nilable(String)

            # Defaults to 1000
            prop :scroll_size, T.nilable(Integer)

            # In time units see https://www.elastic.co/guide/en/elasticsearch/reference/current/api-conventions.html#time-units
            prop :scroll, T.nilable(String)
            prop :search_timeout, T.nilable(String)
            prop :timeout, T.nilable(String)

            # Defaults to OR
            prop :default_operator, T.nilable(DefaultOperator)
            # Defaults to Open
            prop :expand_wildcards, T.nilable(ExpandWildcards)

            # Defaults to true
            prop :allow_no_indices, T.nilable(T::Boolean)

            # Defaults to false
            prop :analyze_wildcard, T.nilable(T::Boolean)
            prop :ignore_unavailable, T.nilable(T::Boolean)
            prop :lenient, T.nilable(T::Boolean)
            prop :refresh, T.nilable(Refresh)


            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                allow_no_indices:,
                analyze_wildcard:,
                analyzer:,
                conflicts: conflicts&.serialize,
                default_operator: default_operator&.serialize,
                df:,
                expand_wildcards: expand_wildcards&.serialize,
                ignore_unavailable:,
                lenient:,
                max_docs:,
                pipeline:,
                preference:,
                q:,
                refresh: refresh&.serialize,
                request_cache:,
                request_per_second:,
                routing:,
                scroll_size:,
                scroll:,
                search_timeout:,
                search_type: search_type&.serialize,
                slices:,
                sort:,
                stats:,
                terminate_after:,
                version:,
                wait_for_active_shards:,
              }.compact
            end
          end
        end
      end
    end
  end
end
