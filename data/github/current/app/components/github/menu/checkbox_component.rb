# typed: true
# frozen_string_literal: true

module GitHub
  module Menu
    class CheckboxComponent < ApplicationComponent
      attr_reader :text, :checked, :replace_text, :input_classes

      def initialize(
        checked:,
        data: {},
        description: nil,
        disabled: false,
        id: nil,
        input_classes: nil,
        name:,
        text:,
        value:,
        required: false
      )
        @checked = checked
        @data = data
        @description = description
        @disabled = disabled
        @id = id
        @input_classes = input_classes
        @name = name
        @text = text
        @value = value
        @required = required
      end

      private

      def required?
        @required
      end
    end
  end
end
