# typed: true
# frozen_string_literal: true

module Site
  module KeyboardShortcuts
    class SectionComponent < ApplicationComponent
      ACCESSIBLE_KEY_NAME = {
        "?": "question mark",
        "/": "forward slash",
        "\\": "back slash",
        "←": "left arrow",
        "↑": "up arrow",
        "→": "right arrow",
        "↓": "down arrow",
        ".": "dot"
      }.freeze

      def initialize(is_open:, title:, shortcuts:)
        @shortcuts = shortcuts
        @title = title
        @is_open = is_open
      end

      private

      def shortcuts
        @shortcuts
      end

      def title
        @title
      end

      def accessible_key_name(key)
        ACCESSIBLE_KEY_NAME.fetch(:"#{key}", nil)
      end

      def is_open?
        @is_open
      end

      def render?
        shortcuts.present? && is_open?
      end
    end
  end
end
