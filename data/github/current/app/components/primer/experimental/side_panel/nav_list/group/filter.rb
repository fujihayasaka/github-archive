# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    class SidePanel::NavList::Group::Filter < Primer::Component
      status :experimental

      attr_reader :button_label

      def initialize(**system_arguments)
        @system_arguments = system_arguments

        @label = system_arguments[:label] || "Filter items"
        @button_label = system_arguments[:button_label] || @label
        @placeholder = system_arguments[:placeholder] || @label
        @src = system_arguments[:src] || "#"
        @input_id ||= system_arguments[:input_id] || self.class.generate_id(base_name: "input")
      end
    end
  end
end
