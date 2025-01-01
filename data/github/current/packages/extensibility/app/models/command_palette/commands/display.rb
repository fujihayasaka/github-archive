# typed: true
# frozen_string_literal: true

module CommandPalette
  module Commands
    class Display
      attr_reader :title, :name, :icon, :hint, :priority

      def initialize(title:, name:, icon:, hint:, priority:)
        @title = title
        @name = name
        @icon = icon
        @hint = hint
        @priority = priority
      end
    end
  end
end
