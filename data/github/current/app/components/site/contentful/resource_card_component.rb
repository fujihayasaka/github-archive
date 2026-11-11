# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    class ResourceCardComponent < ApplicationComponent
      def initialize(title:, text:, link:)
        @title = title
        @text = text
        @link = link
      end

      def render?
        @title.present? && @text.present? && @link.present?
      end
    end
  end
end
