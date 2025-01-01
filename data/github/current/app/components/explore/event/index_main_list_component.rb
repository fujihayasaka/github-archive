# typed: true
# frozen_string_literal: true

module Explore
  module Event
    class IndexMainListComponent < ApplicationComponent
      def initialize(events:)
        @events = events
      end
    end
  end
end
