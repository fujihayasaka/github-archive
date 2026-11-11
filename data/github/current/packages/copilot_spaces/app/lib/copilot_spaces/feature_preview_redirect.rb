# typed: true
# frozen_string_literal: true

module CopilotSpaces
  module FeaturePreviewRedirect
    extend T::Helpers
    extend ActiveSupport::Concern

    requires_ancestor { ApplicationController }

    def copilot_spaces_enabled?
      CopilotSpaces::Enabled.copilot_spaces_enabled_for_user?(current_user)
    end

    def require_copilot_spaces_feature_enabled
      render_404 unless copilot_spaces_enabled?
    end
  end
end
