# typed: true
# frozen_string_literal: true

module Explore
  module Event
    class FeedItemComponent < ApplicationComponent
      include ::ExploreHelper

      def initialize(event:)
        @event = event
      end

      private

      def explore_click_context
        :EVENT_CARD
      end

      def render?
        @event.present?
      end
    end
  end
end
