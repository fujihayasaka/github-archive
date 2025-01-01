# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          module Aggregation
            class TopHits < T::Struct
              # A top_hits metric aggregator keeps track of the most relevant document being aggregated. This aggregator
              # is intended to be used as a sub aggregator, so that the top matching documents can be aggregated per bucket.
              #
              # It is not recommended to use top_hits as a top-level aggregation. If you want to group search hits, use
              # the `collapse` parameter instead: https://www.elastic.co/guide/en/elasticsearch/reference/current/collapse-search-results.html.
              #
              # The top_hits aggregator can effectively be used to group result sets by certain fields via a bucket
              # aggregator. One or more bucket aggregators determines by which properties a result set get sliced into.
              #
              # See https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-metrics-top-hits-aggregation.html
              # for more info.

              include Metricable

              class SourceOptions < T::Struct
                const :includes, T.nilable(T::Array[String])
                const :excludes, T.nilable(T::Array[String])

                sig { returns(T::Hash[Symbol, T.untyped]) }
                def to_hash
                  { includes:, excludes: }.compact
                end
              end

              # Required
              const :slug, Symbol

              # Optional
              const :from, T.nilable(Integer)
              const :size, T.nilable(Integer)
              const :sort, T.nilable(T::Array[T::Hash[T.untyped, T.untyped]])
              const :_source, T.nilable(T.any(T::Boolean, T::Array[String], SourceOptions))
              const :script_fields, T.nilable(T::Hash[Symbol, T.untyped])
              const :docvalue_fields, T.nilable(T::Array[String])
              const :stored_fields, T.nilable(T::Array[String])
              const :version, T.nilable(T::Boolean)
              const :seq_no_primary_term, T.nilable(T::Boolean)
              const :explain, T.nilable(T::Boolean)
              const :highlight, T.nilable(T::Hash[Symbol, T.untyped])
              const :track_scores, T.nilable(T::Boolean)
              const :track_total_hits, T.nilable(T::Boolean)
              const :meta, T.nilable(T::Hash[T.untyped, T.untyped])

              sig { override.returns(Symbol) }
              def aggregation_type_key
                :top_hits
              end

              sig { override.returns(T::Hash[Symbol, T.untyped]) }
              def body
                {
                  from:,
                  size:,
                  sort:,
                  _source: _source&.is_a?(SourceOptions) ? T.cast(_source, SourceOptions).to_hash : _source,
                  script_fields:,
                  docvalue_fields:,
                  stored_fields:,
                  version:,
                  seq_no_primary_term:,
                  explain:,
                  highlight:,
                  track_scores:,
                  track_total_hits:,
                }.compact
              end
            end
          end
        end
      end
    end
  end
end
