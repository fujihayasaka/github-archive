# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Bulk
        module Request
          # A struct representing all possible parameters that can be passed into the bulk_update method. Here is an example
          # of default usage:
          #
          #   bulk_update(<Body>, Params.new(routing: 2))
          #
          # See https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-bulk.html for reference
          class Params < T::Struct
            extend T::Sig

            # See https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-refresh.html for reference
            class Refresh < T::Enum
              enums do
                True = new("true")
                False = new("false")
                WaitFor = new("wait_for")
              end
            end

            # Optional
            prop :_source, T.nilable(T::Boolean)
            prop :_source_excludes, T.nilable(T::Array[String])
            prop :_source_includes, T.nilable(T::Array[String])
            prop :list_executed_pipelines, T.nilable(T::Boolean)
            prop :pipeline, T.nilable(String)
            prop :refresh, T.nilable(Refresh)
            prop :require_alias, T.nilable(T::Boolean)
            prop :routing, T.nilable(Integer)
            prop :timeout, T.nilable(String)
            # wait_for_active_shards can either be "all" or an integer > 0 and < the number of replicas + 1. See
            # https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-index_.html#index-wait-for-active-shards
            # for more information.
            prop :wait_for_active_shards, T.nilable(T.any(String, Integer))

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                _source: _source,
                _source_excludes: _source_excludes,
                _source_includes: _source_includes,
                list_executed_pipelines:,
                pipeline:,
                refresh: refresh&.serialize,
                require_alias:,
                routing:,
                timeout:,
                wait_for_active_shards:,
              }.compact
            end
          end
        end
      end
    end
  end
end
