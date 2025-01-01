# typed: true
# frozen_string_literal: true

module Site
  class VideoPlayerComponent < ApplicationComponent
    include SvgHelper

    renders_one :poster

    def initialize(
      src: nil,
      sources: nil,
      width: 1920,
      height: 1080,
      subtitles: nil,
      theme: nil,
      classes: nil,
      media_element_classes: nil,
      title: nil,
      octicon: "mark-github",
      show_title_bar: true,
      show_play_overlay: true,
      mobile_layout_only: false,
      aria_label: nil
    )
      @src = src
      @sources = sources
      @width = width
      @height = height
      @subtitles = subtitles
      @theme = theme
      @classes = classes
      @media_element_classes = media_element_classes
      @title = title
      @octicon = octicon
      @show_title_bar = show_title_bar
      @show_play_overlay = show_play_overlay
      @mobile_layout_only = mobile_layout_only
      @aria_label = aria_label

      if @subtitles.instance_of?(String)
        @subtitles = [{ src: @subtitles, srclang: "en", default: true }]
      end
    end

    def container_classes
      class_names(
        "d-block media-player-buttons-white media-player-thumb-on-hover",
        @classes
      )
    end

    def media_element_classes
      class_names(
        "d-block position-absolute z-1 rounded-2 width-full height-full top-0 left-0",
        @media_element_classes
      )
    end
  end
end
