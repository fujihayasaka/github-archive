# typed: true
# frozen_string_literal: true

module Explore
  module Spotlight
    class RelatedItemComponent < ApplicationComponent
      include ::TextHelper
      include ::ExploreHelper

      def initialize(spotlight:)
        @spotlight = spotlight
      end

      private

      def render?
        @spotlight.present? && logged_in?
      end

      def explore_click_context
        :SPOTLIGHT_CARD
      end
    end
  end
end
