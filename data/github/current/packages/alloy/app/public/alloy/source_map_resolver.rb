# typed: strict
# frozen_string_literal: true

module Alloy
  class SourceMapResolver
    sig { params(url: String, line: Integer, column: Integer).returns(String) }
    def resolve(url:, line:, column:)
      url
    end

    sig { params(error: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def stacktrace?(error)
      true
    end
  end
end
