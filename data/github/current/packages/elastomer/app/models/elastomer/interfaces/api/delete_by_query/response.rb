# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module DeleteByQuery
        # Response class for Delete By Query API results from Elasticsearch.
        #
        # This class represents the structured response from an Elasticsearch Delete By Query operation,
        # including statistics about the deletion process, timing information, and any failures that occurred.
        #
        # See https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-delete-by-query.html#docs-delete-by-query-api-response-body
        # for reference.
        class Response < T::Struct

          class Retries < T::Struct
            const :bulk, Integer
            const :search, Integer

            sig { params(response: T::Hash[String, T.untyped]).returns(Retries) }
            def self.from_es_response(response)
              attrs = response.deep_symbolize_keys
              new(
                bulk: attrs.dig(:retries, :bulk) || 0,
                search: attrs.dig(:retries, :search) || 0
              )
            end

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              { bulk:, search: }
            end
          end

          const :took, Integer
          const :timed_out, T::Boolean
          const :total, Integer
          const :deleted, Integer
          const :batches, Integer
          const :version_conflicts, Integer
          const :noops, Integer
          const :retries, Retries
          const :throttled_millis, Integer
          const :requests_per_second, Float
          const :throttled_until_millis, Integer
          const :failures, T.nilable(T::Array[Api::Response::FailureCause])

          sig { params(response: T::Hash[String, T.untyped]).returns(Response) }
          def self.from_es_response(response)
            attrs = response.deep_symbolize_keys
            new(
              took: attrs[:took],
              timed_out: attrs[:timed_out],
              total: attrs[:total],
              deleted: attrs[:deleted],
              batches: attrs[:batches],
              version_conflicts: attrs[:version_conflicts],
              noops: attrs[:noops],
              retries: Retries.from_es_response(attrs[:retries]),
              throttled_millis: attrs[:throttled_millis],
              requests_per_second: attrs[:requests_per_second],
              throttled_until_millis: attrs[:throttled_until_millis],
              failures: attrs[:failures]&.map { Api::Response::FailureCause.from_es_response(_1) }
            )
          end

          sig { returns(T::Hash[Symbol, T.untyped]) }
          def to_hash
            {
              took:,
              timed_out:,
              total:,
              deleted:,
              batches:,
              version_conflicts:,
              noops:,
              retries: retries.to_hash,
              throttled_millis:,
              requests_per_second:,
              throttled_until_millis:,
              failures: failures&.map(&:to_hash)
            }
          end
        end
      end
    end
  end
end
