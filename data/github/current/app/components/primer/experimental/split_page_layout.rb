# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    class SplitPageLayout < Primer::Component
      # Defaults we're changing from PageLayout
      PANE_STICKY_DEFAULT = true
      PANE_WIDTH_DEFAULT = :wide
      INNER_SPACING_DEFAULT = :normal

      renders_one :header_region, lambda { |**system_arguments, &block|
        header_arguments = system_arguments.merge(
          divider: :line
        )
        @layout_instance.with_header_region(**header_arguments, &block)
      }

      renders_one :content_region, lambda { |**system_arguments, &block|
        content_arguments = system_arguments.merge(
          data: {}.merge({ target: "split-page-layout.content" }, system_arguments[:data] || {})
        )
        @layout_instance.with_content_region(**content_arguments, &block)
      }

      renders_one :pane_region, lambda { |sticky: PANE_STICKY_DEFAULT, width: PANE_WIDTH_DEFAULT, **system_arguments, &block|
        T.bind(self, Primer::Experimental::SplitPageLayout)

        pane_arguments = system_arguments.merge(
          divider: :line,
          divider_when_narrow: :none,
          classes: class_names("PageLayout-pane--sticky": sticky),
          data: {}.merge({ target: "split-page-layout.pane" }, system_arguments[:data] || {}),
          width: fetch_or_fallback(Primer::Experimental::PageLayout::Pane::WIDTH_OPTIONS, width, PANE_WIDTH_DEFAULT)
        )
        @layout_instance.with_pane_region(**pane_arguments, &block)
      }

      renders_one :footer_region, lambda { |**system_arguments, &block|
        footer_arguments = system_arguments.merge(
          divider: :line
        )
        @layout_instance.with_footer_region(**footer_arguments, &block)
      }

      def initialize(inner_spacing: INNER_SPACING_DEFAULT, **system_arguments)
        arguments = system_arguments.merge(
          tag: :"split-page-layout",
          container_width: :full,
          column_gap: :none,
          row_gap: :none,
          outer_spacing: :none,
          inner_spacing: fetch_or_fallback(Primer::Experimental::PageLayout::INNER_SPACING_OPTIONS, inner_spacing, INNER_SPACING_DEFAULT),
          responsive_variant: :separate_regions
        )

        @layout_instance = Primer::Experimental::PageLayout.new(**arguments)
      end

      def call
        @layout_instance.render_in(self) { content }
      end
    end
  end
end
