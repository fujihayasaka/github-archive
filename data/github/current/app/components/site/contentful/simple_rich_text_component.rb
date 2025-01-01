# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    class SimpleRichTextComponent < ApplicationComponent
      def initialize(text:, classes: [])
        @text = text
        @classes = classes
      end

      def render?
        @text.present?
      end

      def classes
        @classes.join(" ")
      end

      def call
        content_tag(:div, rendered_rich_text, class: classes)
      end

      private

      def rendered_rich_text
        helpers.contentful_rich_text(@text)
      end
    end
  end
end
