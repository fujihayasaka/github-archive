# typed: strict
# frozen_string_literal: true

module Search
  module Queries
    class EmbeddingError < StandardError
      class EmbeddingFetchError < EmbeddingError
        sig { params(error: StandardError).void }
        def initialize(error)
          super("Failed to fetch embedding vector: #{error.message}")
        end
      end

      class InvalidEmbeddingResponseError < EmbeddingError
        sig { params(response_body: T::Hash[String, T.untyped]).void }
        def initialize(response_body)
          super("Invalid embedding response format: #{response_body.inspect}")
        end
      end
    end
  end
end
