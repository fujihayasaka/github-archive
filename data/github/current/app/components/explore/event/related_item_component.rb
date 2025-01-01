# typed: true
# frozen_string_literal: true

module Explore
  module Event
    class RelatedItemComponent < ApplicationComponent
      include ::ExploreHelper

      def initialize(event:)
        @event = event
      end

      private

      def render?
        @event.present?
      end

      def explore_click_context
        :EVENT_CARD
      end
    end
  end
end
