# typed: true
# frozen_string_literal: true

module CommandPalette
  module Results
    class CopyableResult
      attr_reader :object, :display, :group
      delegate :title, :icon, to: :display

      def initialize(object:, display:, copyable_text:, copyable_message:)
        @object = object
        @display = display
        @copyable_text = copyable_text
        @copyable_message = copyable_message
        @group = :commands
      end

      def as_json(*)
        {
          object: @object.as_json(dangerously_allow_all_keys: true),
          title: @display.title,
          icon: @display.icon,
          hint: @display.hint,
          group: @group,
          action: {
            id: @display.name,
            type: "copyable",
            text: @copyable_text,
            message: @copyable_message,
          },
        }
      end
    end
  end
end
