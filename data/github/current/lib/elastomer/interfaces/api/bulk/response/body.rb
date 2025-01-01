# typed: strict
# frozen_string_literal: true

require "elastomer/interfaces/api/bulk/response/item"

module Elastomer
  module Interfaces
    module Api
      module Bulk
        module Response
          class Body < T::Struct
            # Note that this and class and its sub-classes were derived from this documentation:
            #
            # https://www.elastic.co/guide/en/elasticsearch/reference/8.12/docs-bulk.html#bulk-api-response-body

            # Errors and items are mutable to facilitate post-processing of the response,
            # e.g., to exclude errors that we know are safe to ignore.
            prop :errors, T::Boolean
            prop :items, T::Array[Item]
            const :took, Integer

            sig do
              params(
                response: T::Hash[String, T.untyped],
                ignored_errors: T::Array[T::Hash[Symbol, T.untyped]],
              ).returns(Body)
            end
            def self.from_es_response(response, ignored_errors = [])
              new(
                errors: response["errors"],
                items: response["items"].map { |i| Item.from_es_response(i) },
                took: response["took"]
              )
            end

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                errors: errors,
                items: items.map(&:to_hash),
                took: took
              }
            end
          end
        end
      end
    end
  end
end
