# typed: true
# frozen_string_literal: true

module Site
  module Header
    class UnderlineNavTab
      attr_reader :text, :href, :voltron_href, :count, :highlight, :highlight_opts, :data, :icon, :counter_arguments, :data_turbo_frame

      def initialize(text:, href:, icon:, voltron_href: nil, count: nil, highlight: nil, highlight_opts: {}, data: {}, counter_arguments: {}, data_turbo_frame: true)
        @text = text
        @href = href
        @voltron_href = voltron_href
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
