# typed: strict
# frozen_string_literal: true

require "psych/nodes"

module Copilot
  module ContentExclusion
    class Document
      include GitHub::Memoizer
      include DocumentErrorHelpers

      ParsingError = Class.new(StandardError)

      ELEMENT = T.type_alias { { value: String, location: [Integer, Integer] } }

      sig { returns(String) }
      attr_reader :document

      sig { params(document: String, allow_text_based_rules: T::Boolean).void }
      def initialize(document, allow_text_based_rules: false)
        @document = T.let(document, String)
        @allow_text_based_rules = allow_text_based_rules
      end

      sig { returns(T::Array[Rule]) }
      memoize def rules
        return process.value { [] } if GitHub.review_lab?
        start = GitHub::Dogstats.monotonic_time
        cached_value = Copilot.redis.get(cache_key)
        result = T.let([], T::Array[Rule])

        if cached_value.nil?
          result = set_cached_rules
        else
          result = JSON.parse(cached_value).map { |rule| Rule.from_hash(rule) }
        end

        GitHub.dogstats.timing_since("copilot.ignore.document.rules.cache_time", start, tags: ["type:#{cached_value.nil? ? "miss" : "hit"}"])

        result
      rescue JSON::ParserError => error
        GitHub.logger.error("Failed to parse cached rules for document: #{cache_key}", error:)
        Copilot.redis.del(cache_key)
        set_cached_rules
      rescue StandardError => error # rubocop:disable Lint/RescueException
        GitHub.logger.error("Failed to get rules for document: #{cache_key}", error:)
        process.value { [] }
      end

      sig { returns(T::Array[Rule]) }
      memoize def all_scoped_rules
        rules.select(&:is_all_scoped?)
      end

      sig { returns(GitHub::Result) }
      def validate
        process
      end

      private

      sig { returns(T::Array[Rule]) }
      def set_cached_rules
        result = process.value { [] }
        Copilot.redis.set(cache_key, result.to_json)
        result
      end

      sig { returns(String) }
      memoize def cache_key
        [
          "copilot:ignore:document:rules",
          Digest::SHA256.hexdigest(document),
          @allow_text_based_rules
        ].join(":")
      end

      sig { returns(GitHub::Result) }
      def process
        raise NotImplementedError, "needs to be implemented in a subclass"
      end

      module Scope

        # The `REPO` scope represents rules that apply to a specific repository.
        REPO = T.let("repo".freeze, String)
        # The `ALL` scope represents rules that apply to all files in the filesystem, represented by the wildcard (`*`) pattern.
        ALL = T.let("all".freeze, String)
        ALL_PATTERN = T.let('"*"'.freeze, String)

        sig { returns(T::Array[String]) }
        def self.get_scopes
          [ALL, REPO]
        end

        sig { params(pattern: String).returns(T::Boolean) }
        def self.is_all_pattern?(pattern)
          pattern == ALL_PATTERN
        end
      end
    end
  end
end
