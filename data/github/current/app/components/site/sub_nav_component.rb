# typed: true
# frozen_string_literal: true

module Site
  class SubNavComponent < ApplicationComponent
    include SiteHelper
    include HydroHelper

    VERSION = "1.0.5" # Bump this to clear the production cache, if you're making changes to the component

    def initialize(title: nil, url: nil, links: [], ctas: [], ctas_always_visible: false, sticky: true, init_hidden: false, scrollnav: false, align: :left, analytics: {}, classes: nil, tag: nil, render: true, dark: false, style: nil)
      @title = title
      @url = url
      @links = links
      @ctas = ctas.reject { |c| c[:render] == false }
      @ctas_always_visible = ctas_always_visible
      @sticky = sticky
      @init_hidden = init_hidden
      @scrollnav = scrollnav
      @align = align
      @classes = classes
      @analytics = analytics
      @title_data = nil
      @render = render
      @dark = dark
      @request_path = ""
      @tag = tag.present? ? tag : :div
      @style = style

      if @ctas.present?
        @ctas.map do |cta|
          cta[:arrow] = !cta[:url].start_with?("#")
          cta[:classes] = class_names("ml-lg-2 mt-2 mt-lg-0 d-block d-lg-inline-block", cta[:classes])
          cta[:scheme] ||= :muted if cta.equal?(@ctas.last)
        end
      end

      @analytics[:context] ||= @title.downcase.gsub(" ", "_") if @title.present?
      @analytics[:location] ||= "#{scrollnav ? "scrollnav" : "subnav"}"
      @analytics[:tag] = "link"
    end

    def cache_key
      digest = Digest::SHA256.hexdigest("#{@request_path}_logged_#{logged_in? ? "in" : "out"}_#{@title}_#{@url}_#{@links.to_json}_#{@ctas.present? ? @ctas.to_json : "ctas"}_#{@sticky}_#{@init_hidden}_#{@scrollnav}_#{@align}_#{@classes}_#{@tag}_#{@render}_#{@dark}_#{@style}_#{@title_data}")
      "site_sub_nav_#{VERSION}_#{digest}"
    end

    def before_render
      @request_path = request&.path

      @links.each do |link|
        link[:classes] = class_names(
          "sub-nav-mktg-link Link--primary no-underline py-1 py-lg-2",
          "js-scrollnav-item": @scrollnav,
          "active": link[:url] == @request_path
        )

        analytics = @analytics.clone
        analytics_data = analytics_tags_from_content_v2(
          analytics: analytics,
          text: link[:text]
        )

        link[:analytics_data] = analytics_click_attrs_marketing(**analytics_data)
      end

      @ctas.map do |cta|
        cta[:analytics] ||= @analytics.clone
      end

      if @title.present?
        title_analytics = @analytics.clone
        title_data = analytics_tags_from_content_v2(
          analytics: title_analytics,
          text: @title
        )

        @title_data = analytics_click_attrs_marketing(**title_data)
      end
    end

    def container_classes
      class_names(
        "sub-nav-mktg js-toggler-container z-3",
        @classes,
        {
          "js-sticky-state z-3 position-sticky width-full": @sticky,
          "position-relative": !@sticky,
          "init-hidden": @init_hidden,
          "scrollnav": @scrollnav,
          "sub-nav-mktg-shadow": !@scrollnav,
          "ctas-always-visible": @ctas_always_visible,
        }
      )
    end

    def inner_container_classes
      class_names(
        "sub-nav-mktg-wrapper d-flex flex-items-center py-3",
        {
          "px-3 px-md-4 px-lg-5": @title.present?,
          "p-responsive": @title.blank?,
          "container-xl": @align == :center || @title.blank?
        }
      )

    end

    def links_wrapper_classes
      class_names(
        "sub-nav-mktg-links flex-auto f4-mktg d-flex flex-column flex-lg-row",
        "with-title": @title.present?,
        "gap-4": @align == :left,
        "flex-justify-between": @align == :center,
      )
    end

    def render?
      @render
    end
  end
end
