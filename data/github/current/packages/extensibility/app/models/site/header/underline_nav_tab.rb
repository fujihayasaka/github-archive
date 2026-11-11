# typed: true
# frozen_string_literal: true

module Site
  module Header
    class UnderlineNavTab
      attr_reader :text, :href, :count, :highlight, :highlight_opts, :data, :icon, :counter_arguments, :data_turbo_frame

      def initialize(text:, href:, icon:, count: nil, highlight: nil, highlight_opts: {}, data: {}, counter_arguments: {}, data_turbo_frame: true, popover_target: false)
        @text = text
        @href = href
        @count = count
        @highlight = highlight
        @highlight_opts = highlight_opts
        @data = data
        @icon = icon
        @counter_arguments = counter_arguments
        @data_turbo_frame = data_turbo_frame
        @popover_target = popover_target
      end

      def popover_target?
        !!@popover_target
      end

      def classes
        base = "no-wrap js-responsive-underlinenav-item js-selected-navigation-item"
        base += " js-navigation-popover-target" if popover_target?
        base
      end
    end
  end
end
