# typed: strict
# frozen_string_literal: true

module Alloy
  class Response
    PreloadedQueryVariables = T.type_alias { T::Hash[String, T.untyped] }
    PreloadedQueryResult = T.type_alias { T::Hash[String, T.untyped] }
    PreloadedQuery = T.type_alias { { queryId: String, variables: PreloadedQueryVariables, result: PreloadedQueryResult } }

    sig { returns(Integer) }
    attr_reader :status
    sig { returns(T.nilable(String)) }
    attr_accessor :result
    sig { returns(T.nilable(String)) }
    attr_accessor :error
    sig { returns(T.nilable(T::Array[PreloadedQuery])) }
    attr_accessor :preloaded_queries
    sig { returns(T::Array[String]) }
    attr_accessor :dynamic_chunks

    sig { params(status: Integer, result: T.nilable(String), error: T.nilable(String), preloaded_queries: T.nilable(T::Array[PreloadedQuery]), dynamic_chunks: T::Array[String]).void }
    def initialize(status:, result: "", error: nil, preloaded_queries: nil, dynamic_chunks: [])
      @status = status
      @result = result
      @error = error
      @preloaded_queries = preloaded_queries
      @dynamic_chunks = dynamic_chunks
    end

    sig { returns(T::Boolean) }
    def success?
      result.present?
    end

    sig { params(response: Faraday::Response).returns(T.attached_class) }
    def self.from_faraday_response(response)
      if response.body.nil? || !response.success?
        error_message = response.body.nil? ? "Empty response body" : response.body.dup.force_encoding("UTF-8")
        new(status: response.status, error: error_message)
      elsif response.headers["content-type"].include?("application/json")
        json_response = JSON.parse(response.body)

        new(
          status: response.status,
          result: json_response["html"].force_encoding("UTF-8"),
          preloaded_queries: json_response["preloadedQueries"],
          dynamic_chunks: Array(json_response["dynamicChunks"]),
        )
      else
        new(status: response.status, result: response.body.dup.force_encoding("UTF-8"))
      end
    end
  end
end
