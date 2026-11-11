# typed: true
# frozen_string_literal: true

module StatusCheckConfig::Defaults
  module Incomplete
    def state
      StatusCheckConfig::States::INCOMPLETE
    end

    def status_sentence_color_class
      "color-fg-muted"
    end

    def status_icon_color_class
      "neutral-check"
    end

    def check_icon_color_class
      "neutral-check"
    end
  end
end
