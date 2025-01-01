# typed: true
# frozen_string_literal: true

module Pricing
  class FeatureRowComponent < ApplicationComponent
    def initialize(title:, subtitle: nil, description:, render: true, analytics: nil)
      @title = title
      @subtitle = subtitle
      @description = description
      @render = render
      @data = nil
      @analytics = analytics.present? ? analytics : {}
      @analytics[:category] = "Plan card"
    end

    def render?
      @render
    end

    def before_render
      # Generate analytics data from content and merge with other data attributes
      short_title = @title.split(" ").first(6).join(" ")
      @analytics[:action] = "Click to expand"
      analytics = analytics_tags_from_content(analytics: @analytics, text: short_title)
      @analytics = analytics.present? ? analytics_click_attributes(**analytics) : nil
      @data = @analytics.present? && @data.present? ? @data.merge(@analytics) : @data || @analytics
    end

  end
end
