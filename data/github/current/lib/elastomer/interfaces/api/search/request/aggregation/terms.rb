# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          module Aggregation
            class Terms < T::Struct
              # This Struct is meant to closely align with the "Terms" aggregation as documented here:
              # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-terms-aggregation.html
              #
              # Note however that this is not quite a 1:1 mapping, as we have some additional constraints that we need to enforce
              # to ensure clear mapping between aggregation requests and related responses.

              extend T::Helpers
              include Bucketable

              class PartitionOffset < T::Struct
                const :partition, Integer
                const :num_partitions, Integer

                sig { returns(T::Hash[Symbol, Integer]) }
                def to_hash
                  { partition:, num_partitions: }
                end
              end

              class CollectMode < T::Enum
                enums do
                  BreadthFirst = new(:breadth_first)
                  DepthFirst = new(:depth_first)
                end
              end

              class ExecutionHint < T::Enum
                enums do
                  Map = new(:map)
                  GlobalOrdinals = new(:global_ordinals)
                end
              end

              # Required
              const :slug, Symbol
              const :field, String

              # Optional
              const :size, T.nilable(Integer)
              const :shard_size, T.nilable(Integer)
              const :order, T.nilable(T.any(T::Array[T::Hash[Symbol, String]], T::Hash[Symbol, String]))
              const :include, T.nilable(T.any(String, T::Array[String], PartitionOffset))
              const :exclude, T.nilable(T.any(String, T::Array[String]))
              const :missing, T.nilable(String)
              const :min_doc_count, T.nilable(Integer)
              const :shard_min_doc_count, T.nilable(Integer)
              const :show_term_doc_count_error, T.nilable(T::Boolean)
              const :collect_mode, T.nilable(CollectMode)
              const :execution_hint, T.nilable(ExecutionHint)
              const :meta, T.nilable(T::Hash[T.untyped, T.untyped])
              const :aggs, Aggregation::Collection, factory: -> { Aggregation::Collection.new }

              sig { override.returns(Symbol) }
              def aggregation_type_key
                :terms
              end

              sig { override.returns(T::Hash[Symbol, T.untyped]) }
              def body
                {
                  field:,
                  size:,
                  shard_size:,
                  order:,
                  include: include.is_a?(PartitionOffset) ? T.cast(include, PartitionOffset).to_hash : include,
                  exclude:,
                  missing:,
                  min_doc_count:,
                  shard_min_doc_count:,
                  show_term_doc_count_error:,
                  collect_mode: collect_mode&.serialize,
                  execution_hint: execution_hint&.serialize,
                }.compact
              end
            end
          end
        end
      end
    end
  end
end
