# typed: true
# frozen_string_literal: true

module Site
  module Header
    include HydroHelper
    class GlobalSidePanelComponent < SidePanelComponent
      include KeyboardShortcutsHelper
      include ResilienceHelper

      attr_reader :nav_menu_props

      def initialize(load_everything: false, rich_content_enabled: false, nav_menu_props: nil, **system_arguments)
        super(load_everything: load_everything, rich_content_enabled: rich_content_enabled)
        @nav_menu_props = nav_menu_props
      end
    end
  end
end
