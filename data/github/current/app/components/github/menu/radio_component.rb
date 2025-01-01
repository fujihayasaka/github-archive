# typed: true
# frozen_string_literal: true

module GitHub
  module Menu
    class RadioComponent < ApplicationComponent
      attr_reader :text, :checked, :replace_text, :input_classes, :label

      def initialize(
        text:,
        checked:,
        name:,
        value:,
        avatar: nil,
        replace_text: nil,
        description: nil,
        label: nil,
        input_classes: nil,
        id: nil,
        disabled: false,
        data: {},
        required: false,
        octicon: nil
      )
        @name = name
        @checked = checked
        @value = value
        @text = text
        @replace_text = replace_text
        @description = description
        @label = label
        @id = id
        @avatar = avatar
        @disabled = disabled
        @data = data
        @input_classes = input_classes
        @required = required
        @octicon = octicon
      end

      private

      def required?
        @required
      end

      def should_render_avatar?
        @avatar.is_a?(GitHub::AvatarComponent)
      end

      def should_render_octicon?
        @octicon.is_a?(Symbol)
      end

      def should_render_label?
        text.present? && label.present?
      end
    end
  end
end
