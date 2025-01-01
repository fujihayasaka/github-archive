# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module UpdateByQuery
        # This is a struct representing the response from Elasticsearch update_by_query requests. Its self.from_es_response method can/should
        # be used to hydrate it before returning from a method call.
        #
        # See https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-update-by-query.html#docs-update-by-query-api-response-body
        # for more information.
        class Response < T::Struct
          class Retries < T::Struct
            const :bulk, Integer
            const :search, Integer

            sig { params(response: T::Hash[T.untyped, T.untyped]).returns(Retries) }
            def self.from_es_response(response)
              attrs = response.deep_symbolize_keys
              new(attrs)
            end

            sig { returns(T::Hash[Symbol, Integer]) }
            def to_hash
              { bulk:, search: }
            end
          end

          const :took, Integer
          const :timed_out, T::Boolean
          const :total, Integer
          const :updated, Integer
          const :deleted, Integer
          const :batches, Integer
          const :version_conflicts, Integer
          const :noops, Integer
          const :retries, Retries
          const :throttled_millis, Integer
          const :requests_per_second, Float
          const :throttled_until_millis, Integer
          const :failures, T.nilable(T::Array[Api::Response::FailureCause])

          sig { params(response: T::Hash[T.untyped, T.untyped]).returns(Response) }
          def self.from_es_response(response)
            attrs = response.deep_symbolize_keys
            attrs[:failures] = attrs[:failures].map { Api::Response::FailureCause.from_es_response(_1) } if attrs[:failures]
            attrs[:retries] = Retries.from_es_response(attrs[:retries])
            new(attrs)
          end

          sig { returns(T::Hash[Symbol, T.untyped]) }
          def to_hash
            {
              took:,
              timed_out:,
              total:,
              updated:,
              deleted:,
              batches:,
              version_conflicts:,
              noops:,
              retries: retries.to_hash,
              throttled_millis:,
              requests_per_second:,
              throttled_until_millis:,
              failures: failures&.map(&:to_hash),
            }.with_indifferent_access
          end
        end
      end
    end
  end
end
