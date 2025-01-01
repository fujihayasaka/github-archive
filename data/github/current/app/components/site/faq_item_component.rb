# typed: true
# frozen_string_literal: true

module Site
  class FaqItemComponent < ApplicationComponent
    include HydroHelper
    VERSION = "1.0.0"

    def initialize(question: "Question?", answer: nil, render: true, analytics: nil)
      @question = question
      @answer = answer
      @render = render
      @data = nil
      @analytics = analytics.present? ? analytics : {}
    end

    def before_render
      # Generate analytics data from content and merge with other data attributes
      short_question = @question.split(" ").first(6).join(" ")
      @analytics[:action] = "Click to expand"
      @analytics[:category] = @analytics[:category].present? ? @analytics[:category] : "FAQ"
      @analytics[:ref_loc] = @analytics[:ref_loc].present? ? @analytics[:ref_loc] : "FAQ list"
      analytics = analytics_tags_from_content(analytics: @analytics, text: short_question)
      @analytics = analytics.present? ? analytics_click_attributes(**analytics) : nil
      @data = @analytics.present? && @data.present? ? @data.merge(@analytics) : @data || @analytics
    end

    def render?
      @render
    end
  end
end
