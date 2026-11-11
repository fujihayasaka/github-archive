# typed: true
# frozen_string_literal: true

module GitHub
  module Menu
    class ButtonComponent < ApplicationComponent
      attr_reader :text, :checked, :replace_text

      def initialize(text:, type:, description: nil, disabled: false, checked: nil, name: nil, value: nil, replace_text: nil, data: {})
        @name = name
        @checked = checked
        @value = value
        @text = text
        @type = type
        @disabled = disabled
        @description = description
        @replace_text = replace_text
        @data = data
      end

      def role
        @checked.nil? ? "menuitem" : "menuitemradio"
      end

      def checkable?
        %w[menuitemradio menuitemcheckbox].include?(role) && !@checked.nil?
      end
    end
  end
end
