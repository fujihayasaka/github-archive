# typed: true
# frozen_string_literal: true

module Site
  class GlobalBannerComponent < ApplicationComponent
    include SvgHelper

    VERSION = "1.0.0"

    def initialize(uid:, title: nil, link:, link_label:, icon: nil, layout_classes: nil, classes: nil, mode: "dark", analytics: nil, data: {}, cache: true, cache_version: 1, render: true, **options)
      @uid = uid
      @title = title
      @link = link
      @link_label = link_label
      @classes = classes
      @layout_classes = layout_classes
      @icon = icon
      @mode = mode
      @analytics = analytics.present? ? analytics : { category: "global_banner", action: @uid }
      @data = data
      @options = options
      @render = render
    end

    def before_render
      # Generate analytics data from content and merge with other data attributes
      analytics = analytics_tags_from_content(analytics: @analytics, text: @title)
      @analytics = analytics.present? ? analytics_click_attributes(**analytics) : nil
    end

    def container_classes
      class_names(
        "global-banner d-block position-relative lh-condensed",
        @classes,
        @layout_classes,
        "px-4 px-md-5 px-lg-8 text-center text-medium": !@layout_classes.present?
      )
    end

    def icon_src
      @icon.is_a?(Site::Contentful::Asset) ? @icon.absolute_url : @icon
    end

    def cache_key
      digest = Digest::SHA256.hexdigest("#{@uid}_#{@title}_#{@link}_#{@link_label}_#{@icon}_#{@mode}_#{@layout_classes}_#{@classes}_#{@data.present? ? @data.to_json : ""}_#{@render}#{@cache_version}#{@analytics.present? ? @analytics.to_json : ""}")
      "site_global_banner_#{digest}"
    end

    def render?
      @render
    end
  end
end
