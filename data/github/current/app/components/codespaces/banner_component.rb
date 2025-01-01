# typed: true
# frozen_string_literal: true

module Codespaces
  class BannerComponent < ApplicationComponent
    def initialize(style = "")
      @style = style
    end

    def render?
      # codespaces_maintenance_notice is a long-lived feature flag that is used for showing this banner during maintenance window
      # A new UserNotice still needs to created and referenced during each maintenance window
      current_user&.feature_enabled?(:codespaces_maintenance_notice) &&
        !current_user&.dismissed_notice?(UserNotice::CODESPACES_MAINTENANCE_2025_05_28_NOTICE)
    end
  end
end
