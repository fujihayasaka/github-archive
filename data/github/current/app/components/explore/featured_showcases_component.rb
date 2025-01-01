# typed: true
# frozen_string_literal: true

module Explore
  class FeaturedShowcasesComponent < ApplicationComponent
    include HydroHelper
    include ExploreHelper

    def initialize(featured_showcases:, container_id: nil)
      @featured_showcases = featured_showcases
      @container_id = container_id
    end

    private

    def render?
      !@featured_showcases.nil? &&
        @featured_showcases.respond_to?(:each) &&
        @featured_showcases.any? &&
        GitHub.showcase_enabled?
    end
  end
end
