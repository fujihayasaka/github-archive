# typed: true
# frozen_string_literal: true

module CommandPalette
  module Results
    class CommandResult
      attr_reader :object, :display, :group
      delegate :title, :icon, to: :display

      def initialize(object:, display:)
        @object = object
        @display = display
        @group = :commands
      end

      def as_json(*)
        {
          object: @object.as_json(dangerously_allow_all_keys: true),
          title: @display.title,
          icon: @display.icon,
          hint: @display.hint,
          priority: @display.priority,
          group: @group,
          action: {
            id: @display.name,
            type: "command",
          },
        }
      end
    end
  end
end
