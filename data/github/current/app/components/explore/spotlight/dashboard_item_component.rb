# typed: true
# frozen_string_literal: true

module Explore
  module Spotlight
    class DashboardItemComponent < ApplicationComponent
      include ::TextHelper

      def initialize(spotlight:)
        @spotlight = spotlight
      end

      private

      def render?
        @spotlight.present?
      end
    end
  end
end
