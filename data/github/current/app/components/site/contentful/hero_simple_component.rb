# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    class HeroSimpleComponent < ApplicationComponent
      def initialize(heading:, subheading:)
        @heading = heading
        @subheading = subheading
      end

      def render?
        @heading.present? && @subheading.present?
      end
    end
  end
end
