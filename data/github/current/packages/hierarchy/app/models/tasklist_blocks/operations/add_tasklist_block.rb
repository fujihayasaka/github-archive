# typed: true
# frozen_string_literal: true

require "commonmarker"

module TasklistBlocks
  module Operations
    class AddTasklistBlock
      extend T::Sig
      include Parseable

      # Check or uncheck a task list item.
      #
      # text - The Markdown String containing the task list to operate on.
      #
      # Returns the mutated Markdown String or nil if the selection failed.
      sig { params(text: T.nilable(String)).returns(T.nilable(String)) }
      def call(text)
        return if text.nil?
        spacing = text.empty? ? "" : "\n"
        text += "#{spacing}\`\`\`[tasklist]\n### Tasks\n\`\`\`\n"
        text
      end
    end
  end
end
