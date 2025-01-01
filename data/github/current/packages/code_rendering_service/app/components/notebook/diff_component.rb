# typed: true
# frozen_string_literal: true
module Notebook
  # A viewscreen diff is a rendered version of a file in the diff view
  class DiffComponent < CodeRenderingService::DiffComponent
    include BlobHelper
    extend T::Sig

    SUPPORTED_VIEWS = {
      ipynb: [:diff],
    }.freeze

    FLAGGED_FEATURES = [:ipynb].freeze

    def flagged_features
      FLAGGED_FEATURES
    end

    sig { returns(String) }
    def host_url
      Notebook.host_url
    end

    sig { returns(T.nilable(T::Boolean)) }
    def supports_view?
      return false if GitHub.enterprise?
      super
    end

    private

    def enabled_for_user?(_)
      current_user&.feature_preview_enabled?("ipynb-diff")
    end

    def supported_views
      SUPPORTED_VIEWS
    end
  end
end
