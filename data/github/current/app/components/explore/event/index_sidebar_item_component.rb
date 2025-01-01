# typed: true
# frozen_string_literal: true

module Explore
  module Event
    class IndexSidebarItemComponent < ApplicationComponent
      def initialize(event:)
        @event = event
      end

      private

      def render?
        @event.present?
      end
    end
  end
end
