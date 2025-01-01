# typed: true
# frozen_string_literal: true

module Explore
  class TrendingComponent < ApplicationComponent
    include ExploreHelper
    include AvatarHelper

    def initialize(trending_repos:, explore_period:, container_id: nil)
      @trending_repos = trending_repos
      @explore_period = explore_period
      @container_id = container_id
    end

    private

    def render?
      !@trending_repos.blank? && ExploreHelper::DATE_OPTIONS.has_key?(@explore_period)
    end
  end
end
