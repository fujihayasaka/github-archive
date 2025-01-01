# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class ExposureAnalysisComponent < ApplicationComponent
    attr_reader :aleph_response

    def initialize(loading: false, aleph_response: nil)
      @loading = loading
      @aleph_response = aleph_response
    end

    def render?
      loading? || vulnerable?
    end

    def loading?
      @loading
    end

    def vulnerable?
      location_count > 0
    end

    def location_count
      (aleph_response&.data&.references || []).flat_map(&:locations).count
    end
  end
end
