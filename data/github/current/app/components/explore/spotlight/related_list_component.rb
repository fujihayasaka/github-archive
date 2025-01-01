# typed: true
# frozen_string_literal: true

module Explore
  module Spotlight
    class RelatedListComponent < ApplicationComponent
      def initialize(spotlights:)
        @spotlights = spotlights
      end

      private

      def render?
        @spotlights&.any?
      end
    end
  end
end
