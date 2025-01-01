# typed: true
# frozen_string_literal: true

module Explore
  module Event
    class RelatedListComponent < ApplicationComponent
      def initialize(events:)
        @events = events
      end

      private

      def render?
        @events.present? && @events.any?
      end
    end
  end
end
