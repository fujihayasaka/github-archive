# typed: true
# frozen_string_literal: true

module Explore
  class StarsComponent < ApplicationComponent
    include ExploreHelper
    include AvatarHelper
    include ::TextHelper # app/helpers/text_helper.rb, not ActionView::Helpers::TextHelper

    def initialize(stars:, explore_period:)
      @stars = stars
      @explore_period = explore_period
    end

    private

    def render?
      ExploreHelper::DATE_OPTIONS.has_key?(@explore_period)
    end
  end
end
