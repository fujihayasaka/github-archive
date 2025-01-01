# typed: true
# frozen_string_literal: true

module Site
  class EyebrowBannerComponent < ApplicationComponent
    include SvgHelper

    VERSION = "1.0.1"

    def initialize(title:, url:, icon: nil, label: nil, label_classes: nil, subtitle: nil, analytics: nil, data: nil, cache: true, cache_version: 1, render: true, **options)
      @title = title
      @url = url
      @icon = icon
      @label = label
      @label_classes = label_classes
      @subtitle = subtitle
      @analytics = analytics.present? ? analytics : { category: "Eyebrow Banner", action: "click", ref_loc: "hero" }
      @data = data
      @options = options
      @render = render
    end

    def before_render
      # Generate analytics data from content and merge with other data attributes
      analytics = analytics_tags_from_content(analytics: @analytics, text: @title)
      @analytics = analytics.present? ? analytics_click_attributes(**analytics) : nil
      @data = @analytics.present? && @data.present? ? @data.merge(@analytics) : @data || @analytics
    end

    def label_classes
      class_names(
        "flex-grow-0 flex-shrink-0 mr-3",
        @label_classes,
        {
          "text-bold text-uppercase text-gradient-mktg": !@label_classes.present?,
        }
      )
    end

    def icon_src
      @icon.is_a?(Site::Contentful::Asset) ? @icon.absolute_url : @icon
    end

    def cache_key
      digest = Digest::SHA256.hexdigest("#{@title}_#{icon_src}_#{@subtitle}_#{@label}_#{@label_classes}_#{@data.present? ? @data.to_json : ""}_#{@render}#{@cache_version}#{@analytics.present? ? @analytics.to_json : ""}")
      "site_eyebrow_banner_#{digest}"
    end

    def render?
      @render
    end
  end
end
