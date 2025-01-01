# typed: true
# frozen_string_literal: true

module CommandPalette
  module Commands
    class Response
      ACTION_DISPLAY_FLASH = "displayFlash"

      attr_reader :action, :arguments

      def initialize(action:, arguments: {})
        @action = action
        @arguments = arguments
      end
    end
  end
end
