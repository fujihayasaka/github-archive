# typed: true
# frozen_string_literal: true

module Users
  module Contributions
    class YearDropdownComponent < ApplicationComponent
      include ProfilesHelper

      def initialize(collector:, org:)
        @collector = collector
        @org = org
      end

      def render?
        current_user&.feature_enabled?(:mobile_year_picker)
      end

      attr_reader :collector, :org
      delegate :profile_click_tracking_attrs, to: :helpers

      def collection_year
        collector.started_at.in_time_zone(Time.zone).year
      end
    end
  end
end
