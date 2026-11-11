# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          class Params < T::Struct
            # This is mostly modeled from the Elasticsearch Search API documentation:
            # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-search.html#search-search-api-query-params            #
            #
            # But there are minor adjustments based on what the Elastomer Client library expects. See:
            # https://github.com/github/elastomer-client/blob/main/lib/elastomer_client/client/docs.rb

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

            class SuggestMode < T::Enum
              enums do
                Always = new("always")
                Missing = new("missing")
                Popular = new("popular")
              end
            end

            # See https://www.elastic.co/guide/en/elasticsearch/reference/current/sort-search-results.html for reference
            Sort = T.type_alias do
              T.any(
                String,
                T::Array[
                  T.any(
                    String,
                    T::Hash[Symbol, T.untyped]
                  )
                ]
              )
            end

            const :allow_no_indices, T.nilable(T::Boolean)
            const :allow_partial_search_results, T.nilable(T::Boolean)
            const :analyzer, T.nilable(String)
            const :analyze_wildcard, T.nilable(T::Boolean)
            const :batched_reduce_size, T.nilable(Integer)
            const :ccs_minimize_roundtrips, T.nilable(T::Boolean)
            const :default_operator, T.nilable(DefaultOperator)
            const :df, T.nilable(String)
            const :docvalue_fields, T.nilable(String)
            const :expand_wildcards, T.nilable(ExpandWildcards)
            const :explain, T.nilable(T::Boolean)
            const :from, T.nilable(Integer)
            const :ignore_throttled, T.nilable(T::Boolean)
            const :include_named_queries_score, T.nilable(T::Boolean)
            const :ignore_unavailable, T.nilable(T::Boolean)
            const :lenient, T.nilable(T::Boolean)
            const :max_concurrent_shard_requests, T.nilable(Integer)
            const :pre_filter_shard_size, T.nilable(Integer)
            const :preference, T.nilable(String)
            const :request_cache, T.nilable(T::Boolean)
            const :rest_total_hits_as_int, T.nilable(T::Boolean)
            const :routing, T.nilable(String)
            const :scroll, T.nilable(String)
            const :search_after, T.nilable(T::Array[T.any(Integer, String)])
            const :search_type, T.nilable(SearchType)
            const :seq_no_primary_term, T.nilable(T::Boolean)
            const :size, T.nilable(Integer)
            const :sort, T.nilable(Sort)
            const :_source, T.nilable(T.any(T::Boolean, String, T::Array[String]))
            const :_source_excludes, T.nilable(String)
            const :_source_includes, T.nilable(String)
            const :stats, T.nilable(String)
            const :stored_fields, T.nilable(String)
            const :suggest_field, T.nilable(String)
            const :suggest_mode, T.nilable(SuggestMode)
            const :suggest_size, T.nilable(Integer)
            const :suggest_text, T.nilable(String)
            const :terminate_after, T.nilable(Integer)
            const :timeout, T.nilable(String)
            const :track_scores, T.nilable(T::Boolean)
            const :track_total_hits, T.nilable(T.any(T::Boolean, Integer))
            const :typed_keys, T.nilable(T::Boolean)
            const :version, T.nilable(T::Boolean)

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                allow_no_indices:,
                allow_partial_search_results:,
                analyzer:,
                analyze_wildcard:,
                batched_reduce_size:,
                ccs_minimize_roundtrips:,
                default_operator: default_operator&.serialize,
                df:,
                docvalue_fields:,
                expand_wildcards: expand_wildcards&.serialize,
                explain:,
                from:,
                ignore_throttled:,
                include_named_queries_score:,
                ignore_unavailable:,
                lenient:,
                max_concurrent_shard_requests:,
                pre_filter_shard_size:,
                preference:,
                request_cache:,
                rest_total_hits_as_int:,
                routing:,
                scroll:,
                search_after:,
                search_type: search_type&.serialize,
                seq_no_primary_term:,
                size:,
                sort:,
                _source: _source,
                _source_excludes: _source_excludes,
                _source_includes: _source_includes,
                stats:,
                stored_fields:,
                suggest_field:,
                suggest_mode: suggest_mode&.serialize,
                suggest_size:,
                suggest_text:,
                terminate_after:,
                timeout:,
                track_scores:,
                track_total_hits:,
                typed_keys:,
                version:,
              }.compact
            end
          end
        end
      end
    end
  end
end
