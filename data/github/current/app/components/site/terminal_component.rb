# typed: true
# frozen_string_literal: true

module Site
  class TerminalComponent < ApplicationComponent
    include SiteHelper

    def container_classes
      class_names(
        "terminal-mktg text-mono",
        @classes,
        {
          "rounded-2": @rounded,
          "js-type-in": @trigger_self,
          "js-type-in-item": !@trigger_self,
        },
      )
    end

    def initialize(classes: nil, dark: true, rounded: true, trigger_self: true, type_delay: nil, type_row_delay: nil, window_controls: false, window_title: nil, directory: nil, rows:)
      @classes = classes
      @dark = dark
      @rounded = rounded
      @trigger_self = trigger_self
      @type_delay = type_delay
      @type_row_delay = type_row_delay
      @window_controls = window_controls
      @window_title = window_title
      @directory = directory
      @rows = rows
    end
  end
end
