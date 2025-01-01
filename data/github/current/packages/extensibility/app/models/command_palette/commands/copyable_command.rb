# typed: true
# frozen_string_literal: true

module CommandPalette
  module Commands
    class CopyableCommand < ApplicationCommand
      def copyable_text
        raise NotImplementedError
      end

      def copyable_message
        raise NotImplementedError
      end

      def to_result
        Results::CopyableResult.new(
          object: scope.object,
          display: self.display,
          copyable_text: self.copyable_text,
          copyable_message: self.copyable_message
        )
      end
    end
  end
end
