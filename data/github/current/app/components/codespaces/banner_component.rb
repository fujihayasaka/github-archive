# typed: true
# frozen_string_literal: true

module Codespaces
  class BannerComponent < ApplicationComponent
    MESSAGE = "Codespaces will be undergoing maintenance in Europe and Southeast Asia from 17:00 UTC Friday 28 February to 02:00 UTC Saturday 1 March. Users may experience connection issues during this time."
    def initialize(style = "")
      @message = MESSAGE
      @style = style
    end

    def render?
      GitHub.flipper[:codespaces_connection_issues_banner].enabled?(current_user) &&
        !current_user&.dismissed_notice?(UserNotice::CODESPACES_MAINTENANCE_NOTICE)
    end
  end
end
