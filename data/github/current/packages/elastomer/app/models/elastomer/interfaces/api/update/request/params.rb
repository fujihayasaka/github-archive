# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Update
        module Request
          # A struct representing all possible parameters that can be passed into the update method. Here is an example
          # of default usage:
          #
          #   update(<Body>, Params.new(id: 1, routing: 2))
          #
          # See https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-update.html for reference
          class Params < T::Struct
            # See https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-refresh.html for reference
            class Refresh < T::Enum
              enums do
                True = new("true")
                False = new("false")
                WaitFor = new("wait_for")
              end
            end

            # Required
            const :id, T.any(Integer, String)

            # Optional
            prop :_source, T.nilable(T::Boolean)
            prop :_source_excludes, T.nilable(T::Array[String])
            prop :_source_includes, T.nilable(T::Array[String])
            prop :if_seq_no, T.nilable(Integer)
            prop :if_primary_term, T.nilable(Integer)
            prop :require_alias, T.nilable(T::Boolean)
            prop :refresh, T.nilable(Refresh)
            prop :retry_on_conflict, T.nilable(Integer)
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
                id:,
                if_seq_no:,
                if_primary_term:,
                require_alias:,
                refresh: refresh&.serialize,
                retry_on_conflict:,
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
