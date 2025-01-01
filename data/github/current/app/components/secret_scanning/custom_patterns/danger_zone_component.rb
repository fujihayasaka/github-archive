# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    class DangerZoneComponent < ApplicationComponent
      attr_reader :pattern_state, :pattern, :remove_pattern_path

      def initialize(pattern_state:, pattern:, remove_pattern_path:)
        @pattern_state = pattern_state
        @pattern = pattern
        @remove_pattern_path = remove_pattern_path
      end

      def section_heading
        action_string = "Delete"
        if @pattern_state == :unpublished
          action_string = "Discard"
        end

        "#{action_string} this pattern"
      end

      def section_description
        return "Once you discard this pattern, dry run results will be lost." if @pattern_state == :unpublished
        "Once you delete this pattern, it will stop scanning repositories."
      end
    end
  end
end
