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
    attr_reader :result
    sig { returns(T.nilable(String)) }
    attr_accessor :error
    sig { returns(T.nilable(T::Array[PreloadedQuery])) }
    attr_accessor :preloaded_queries

    sig { params(status: Integer, result: T.nilable(String), error: T.nilable(String), preloaded_queries: T.nilable(T::Array[PreloadedQuery])).void }
    def initialize(status:, result: "", error: nil, preloaded_queries: nil)
      @status = status
      @result = result
      @error = error
      @preloaded_queries = preloaded_queries
    end

    sig { returns(T::Boolean) }
    def success?
      result.present?
    end

    sig { params(response: Faraday::Response).returns(T.attached_class) }
    def self.from_faraday_response(response)
      if response.body.nil? || !response.success?
        new(status: response.status, error: response.body.dup.force_encoding("UTF-8"))
      elsif response.headers["content-type"].include?("application/json")
        # Alloy is an internal service and we have full control over it,
        # so we can assume that it will always return a safe response.
        json_response = JSON.parse(response.body)
        new(
          status: response.status,
          result: json_response["html"].force_encoding("UTF-8"),
          preloaded_queries: json_response["preloadedQueries"],
        )
      else
        new(status: response.status, result: response.body.dup.force_encoding("UTF-8"))
      end
    end
  end
end
