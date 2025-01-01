# typed: true
# frozen_string_literal: true

module StatusCheckConfig::Defaults
  module Pending
    def state
      StatusCheckConfig::States::PENDING
    end

    def sentence_for_status
      "Waiting to hear about"
    end

    def status_sentence_color_class
      "color-fg-muted"
    end

    def status_icon_color_class
      "hx_dot-fill-pending-icon"
    end
  end
end
