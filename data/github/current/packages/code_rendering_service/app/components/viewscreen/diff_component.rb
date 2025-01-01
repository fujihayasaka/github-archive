# typed: true
# frozen_string_literal: true

module Viewscreen
  # A viewscreen diff is a rendered version of a file in the diff view
  class DiffComponent < CodeRenderingService::DiffComponent
    include BlobHelper

    SUPPORTED_VIEWS = {
      svg: [:diff],
      img: [:diff],
    }.freeze

    FLAGGED_FEATURES = [].freeze


    def flagged_features
      FLAGGED_FEATURES
    end

    def host_url
      Viewscreen.host_url
    end

    def rich_view_toggleable?
      return false unless supports_view?
      return false if diff.binary?
      return false if @render_type == :img
      true
    end

    def default_to_rich_diff_view?
      return false unless supports_view?
      return true if diff.binary?
      true
    end

    private

    def supported_views
      SUPPORTED_VIEWS
    end
  end
end
