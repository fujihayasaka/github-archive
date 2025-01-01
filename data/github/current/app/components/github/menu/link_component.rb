# typed: true
# frozen_string_literal: true

module GitHub
  module Menu
    class LinkComponent < ApplicationComponent
      attr_reader :text, :checked, :replace_text

      def initialize(href:, text: nil, checked: nil, replace_text: nil, description: nil, label: nil, avatar: nil, classes: "", octicon: nil, data: {})
        @href = href
        @checked = checked
        @text = text
        @replace_text = replace_text
        @description = description
        @label = label
        @avatar = avatar
        @data = data
        @classes = classes
        @octicon = octicon
      end

      def role
        @checked.nil? ? "menuitem" : "menuitemradio"
      end

      def checkable?
        %w[menuitemradio menuitemcheckbox].include?(role) && !@checked.nil?
      end

      def classes
        class_names("SelectMenu-item", @classes)
      end

      def should_render_avatar?
        @avatar.is_a?(GitHub::AvatarComponent)
      end

      def should_render_octicon?
        @octicon.is_a?(Symbol)
      end
    end
  end
end
