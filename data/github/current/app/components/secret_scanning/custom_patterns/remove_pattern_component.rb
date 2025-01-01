# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    class RemovePatternComponent < ApplicationComponent
      attr_reader :id, :pattern_state, :display_name, :scope, :style

      def initialize(id:, pattern_state:, display_name:, scope:, style:)
        @id = id
        @pattern_state = pattern_state
        @display_name = display_name
        @scope = scope
        @style = style
      end

      def delete_confirmation_scope_text
        return "this repository" if scope == :repo_scope

        "all repositories with GitHub Advanced Security enabled"
      end

      def remove_action_text
        return "Discard" if pattern_state == :unpublished
        "Delete"
      end
    end
  end
end
