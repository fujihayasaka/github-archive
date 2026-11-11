# typed: true
# frozen_string_literal: true

module Site
  class AudioPlayerComponent < ApplicationComponent
    include SvgHelper

    def initialize(
      src: nil,
      sources: nil,
      theme: "default",
      classes: nil,
      title: nil,
      mobile_layout_only: false,
      aria_label: nil,
      download_src: nil
    )
      @src = src
      @sources = sources
      @theme = theme
      @classes = classes
      @title = title
      @mobile_layout_only = mobile_layout_only
      @aria_label = aria_label
      @download_src = download_src
    end

    def container_classes
      class_names(
        "media-player-thumb-on-hover media-player-square-sliders media-player-thumb-white d-flex flex-column flex-items-center width-full",
        @classes,
        {
          "flex-md-row": !@mobile_layout_only
        }
      )
    end
  end
end
