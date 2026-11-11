# typed: strict
# frozen_string_literal: true

module Elastomer
  # Shared vector math utilities for semantic search indexing and querying.
  module VectorUtils
    # Returns only the first embedding from the inference response. This assumes
    # the input text is short enough to fit in a single chunk (e.g. a search query).
    # If the text is long enough that ES chunks it into multiple embeddings, only
    # the first chunk's vector is returned and the rest are silently dropped,
    # losing some precision. Use fetch_all_embeddings for long-form text.
    #
    # When normalize: true, L2-normalizes the vector to unit length for
    # dot_product similarity which strictly requires ||v|| = 1.
    sig { params(index: T.untyped, text: String, inference_id: String, normalize: T::Boolean).returns(T.nilable(T::Array[Float])) }
    def self.fetch_embedding(index, text, inference_id:, normalize: false)
      body = fetch_inference_response(index, text, inference_id: inference_id)
      embedding = body.dig("text_embedding", 0, "embedding")
      return nil if embedding.nil?

      normalize ? l2_normalize(embedding) : embedding
    end

    # Returns all chunk embeddings from the inference response.
    # The inference endpoint may chunk long text and return multiple embeddings.
    #
    # When normalize: true, L2-normalizes each vector to unit length for
    # dot_product similarity which strictly requires ||v|| = 1.
    sig { params(index: T.untyped, text: String, inference_id: String, normalize: T::Boolean).returns(T::Array[T::Array[Float]]) }
    def self.fetch_all_embeddings(index, text, inference_id:, normalize: false)
      body = fetch_inference_response(index, text, inference_id: inference_id)
      chunks = body["text_embedding"]
      return [] unless chunks.is_a?(Array)

      embeddings = chunks.filter_map { |chunk| chunk["embedding"] }
      normalize ? embeddings.map { |vec| l2_normalize(vec) } : embeddings
    end

    # L2-normalizes a vector to unit length so it is compatible with ES
    # dot_product similarity, which strictly requires ||v|| = 1.
    #
    # Returns the original vector unchanged if it is already unit-length
    # or has zero magnitude.
    sig { params(vector: T::Array[Float]).returns(T::Array[Float]) }
    def self.l2_normalize(vector)
      magnitude = Math.sqrt(vector.sum { |x| x * x })
      return vector if magnitude.zero? || (magnitude - 1.0).abs < 1e-12

      vector.map { |x| x / magnitude }
    end

    class << self
      private

      # Calls the ES inference endpoint and returns the full response body hash.
      sig { params(index: T.untyped, text: String, inference_id: String).returns(T::Hash[String, T.untyped]) }
      def fetch_inference_response(index, text, inference_id:)
        response = index.client.post(
          "/_inference/{task_type}/{inference_id}",
          {
            task_type: "text_embedding",
            inference_id: inference_id,
            body: { input: text },
            rest_api: "inference.inference"
          }
        )

        response.body
      end
    end
  end
end
