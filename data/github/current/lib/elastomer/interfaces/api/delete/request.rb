# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Delete
        module Request
          class Params < T::Struct
            # A struct representing all possible parameters that can be passed into the delete method. Here is an example
            # of default usage:
            #
            #   delete(Params.new(id: 1, routing: 2))
            #
            # See https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-delete.html for reference
            extend T::Sig

            # See https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-refresh.html for reference
            class Refresh < T::Enum
              enums do
                True = new("true")
                False = new("false")
                WaitFor = new("wait_for")
              end
            end

            class VersionType < T::Enum
              enums do
                External = new("external")
                ExternalGte = new("external_gte")
              end
            end

            # Required
            prop :id, Integer

            # Optional
            prop :routing, T.nilable(Integer)
            prop :if_seq_no, T.nilable(Integer)
            prop :if_primary_term, T.nilable(Integer)
            prop :refresh, T.nilable(Refresh)
            prop :timeout, T.nilable(String)
            prop :version, T.nilable(Integer)
            prop :version_type, T.nilable(VersionType)
            prop :wait_for_active_shards, T.nilable(T.any(Integer, String))

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                id:,
                if_seq_no:,
                if_primary_term:,
                refresh: refresh&.serialize,
                routing:,
                timeout:,
                version:,
                version_type: version_type&.serialize,
                wait_for_active_shards:,
              }.compact
            end
          end
        end
      end
    end
  end
end
