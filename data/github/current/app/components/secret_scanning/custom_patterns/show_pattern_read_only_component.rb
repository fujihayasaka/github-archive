# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    class ShowPatternReadOnlyComponent < ApplicationComponent
      attr_reader :pattern, :test_pattern_path, :remove_pattern_path

      def initialize(
        pattern:,
        test_pattern_path:,
        remove_pattern_path:
      )
        @pattern = pattern
        @test_pattern_path = test_pattern_path
        @remove_pattern_path = remove_pattern_path
      end

      def pattern_state
        @pattern.state.downcase
      end

      def start_delimiter
        @pattern.post_processing.start_delimiter
      end

      def end_delimiter
        @pattern.post_processing.end_delimiter
      end

      def post_processing_must_match
        @pattern.post_processing.must_match
      end

      def post_processing_must_not_match
        @pattern.post_processing.must_not_match
      end
    end
  end
end
