# typed: true
# frozen_string_literal: true

module Explore
  module Event
    class IndexListComponent < ApplicationComponent
      def initialize(hosted_events:, sponsored_events:)
        @hosted_events = hosted_events
        @sponsored_events = sponsored_events
      end
    end
  end
end
