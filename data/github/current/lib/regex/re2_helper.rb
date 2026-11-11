# typed: strict
# frozen_string_literal: true

require "re2"

module Regex
  class RE2Helper
    sig { void }
    def initialize
      @compilation_cache = T.let({}, T::Hash[String, RE2::Regexp])
    end

    sig { params(value: String, regex: String).returns(T::Boolean) }
    def matches?(value, regex)
      compiled_regex = compile(regex)
      return false unless compiled_regex.ok?

      compiled_regex =~ value
    end

    sig { params(regex: String).returns(T::Boolean) }
    def is_valid?(regex)
      return true if @compilation_cache.key?(regex)

      compiled_regex = compile(regex)
      compiled_regex.ok?
    end

    private

    sig { params(regex: String).returns(RE2::Regexp) }
    def compile(regex)
      cached_result = @compilation_cache[regex]
      return cached_result if cached_result
      @compilation_cache[regex] = RE2::Regexp.new(regex)
    end
  end
end
