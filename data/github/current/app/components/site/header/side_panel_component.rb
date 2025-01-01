# typed: true
# frozen_string_literal: true

module Site
  module Header
    class SidePanelComponent < ApplicationComponent
      def initialize(load_everything: false, rich_content_enabled: false)
        @load_everything = load_everything
        @rich_content_enabled = rich_content_enabled
      end

      # This is false when the side panel is degraded due to a cluster dependency outage.
      def rich_content_enabled?
        !!@rich_content_enabled
      end

      # To avoid a performance burden on the initial page request, this component is initially rendered
      # in a placeholder state as a slot inside DeferredSidePanelComponent,
      # which automatically requests the full version of the component after the page has loaded.
      # When it's in a placeholder state, this component will only show static navigation links + a loading spinner.
      def placeholder?
        return false unless rich_content_enabled?
        !load_everything?
      end

      def trigger_data
        default_action = "click:deferred-side-panel#panelOpened"
        return { action: default_action } unless placeholder?

        # Sets the data attribute so that the deferred-side-panel component can send the request
        # for the full panel as soon as the user hovers over the trigger button.
        { action: "click:deferred-side-panel#loadPanel #{default_action}" }
      end

      def panel_data
        { target: "deferred-side-panel.panel" }
      end

      def analytics_attributes(key)
        analytics_click_attributes(
          category: "Global navigation",
          action: key,
        )
      end

      # When this is true, the component will render all sections.
      def load_everything?
        !!@load_everything
      end

      def tracking_name(name)
        name = "site/header/#{name}"
        name << "_rich" if rich_content_enabled?
        name
      end

      def tracking_tags
        ["placeholder:#{ placeholder? }"]
      end
    end
  end
end
