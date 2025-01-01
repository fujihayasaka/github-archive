# typed: true
# frozen_string_literal: true

module Site
  module Header
    class UnderlineNavTab
      attr_reader :text, :href, :count, :highlight, :highlight_opts, :data, :icon, :counter_arguments, :data_turbo_frame

      def initialize(text:, href:, icon:, count: nil, highlight: nil, highlight_opts: {}, data: {}, counter_arguments: {}, data_turbo_frame: true)
        @text = text
        @href = href
        @count = count
        @highlight = highlight
        @highlight_opts = highlight_opts
        @data = data
        @icon = icon
        @counter_arguments = counter_arguments
        @data_turbo_frame = data_turbo_frame
      end
    end
  end
end
