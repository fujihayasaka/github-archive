# typed: true
# frozen_string_literal: true
module Notebook
  class ViewComponent < CodeRenderingService::ViewComponent
    FLAG_PREFIX = "notebook".freeze

    SUPPORTED_VIEWS = {
      ipynb: [:view],
    }.freeze
    FLAGGED_FEATURES = [].freeze

    def flag_prefix
      FLAG_PREFIX
    end

    def hide_iframe
      'style="display: none; visibility: hidden;"'
    end

    def flagged_features
      FLAGGED_FEATURES
    end

    def host_url
      Notebook.host_url
    end

    private

    def supported_views
      SUPPORTED_VIEWS
    end
  end
end
