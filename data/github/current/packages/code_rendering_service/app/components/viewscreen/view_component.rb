# typed: true
# frozen_string_literal: true
require_relative "../code_rendering_service/base_component"

module Viewscreen
  class ViewComponent < CodeRenderingService::ViewComponent
    SUPPORTED_VIEWS = {
      solid: [:view],
      geojson: [:view, :preview],
      svg: [:view, :image],
      pdf: [:view, :image],
      psd: [:view, :image],
      topojson: [:view, :preview],
      mermaid: [:view, :preview],
    }.freeze
    FLAGGED_FEATURES = [].freeze

    def host_url
      Viewscreen.host_url
    end

    def supports_view?
      super
    end

    private

    def supported_views
      SUPPORTED_VIEWS
    end

    def flagged_features
      FLAGGED_FEATURES
    end
  end
end
