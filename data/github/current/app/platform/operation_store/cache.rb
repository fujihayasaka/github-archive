# typed: true
# frozen_string_literal: true
require "lru_redux"

module Platform
  module OperationStore
    class Cache
      extend T::Sig

      # Generates a cache key for a given operation ID
      sig { params(operation_id: String).returns(String) }
      def self.cache_key(operation_id)
        "#{GraphQL::VERSION}:graphql_operation:#{operation_id}"
      end

      # Attempts to fetch the operation from the cache
      # returns nil if operation does not exist
      sig { params(operation_id: String).returns(T.nilable(T::Array[T.untyped])) }
      def self.fetch(operation_id)
        if value = GitHub.cache.get(cache_key(operation_id))
          marshaled_body, catalog_service = value
          begin
            if catalog_service.blank?
              raise(Platform::Errors::Internal, "Operation catalog service is not set")
            end
            [Marshal.load(marshaled_body), catalog_service]
          rescue StandardError => e # rubocop:todo Lint/GenericRescue
            Failbot.report(e)
            nil
          end
        else
          nil
        end
      end

      # Stores a GraphQL document and associated catalog service in the cache
      sig { params(operation_id: String, graphql_document: T.untyped, catalog_service: String).void }
      def self.write(operation_id, graphql_document, catalog_service)
        GitHub.cache.set(cache_key(operation_id), [Marshal.dump(graphql_document), catalog_service], 1.hour)
      end
    end
  end
end
