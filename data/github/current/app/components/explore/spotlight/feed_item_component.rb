# typed: true
# frozen_string_literal: true

module Explore
  module Spotlight
    class FeedItemComponent < ApplicationComponent
      include ::TextHelper
      include ::ExploreHelper

      def initialize(spotlight:)
        @spotlight = spotlight
      end

      private

      def explore_click_context
        :SPOTLIGHT_CARD
      end

      def render?
        @spotlight.present?
      end
    end
  end
end
