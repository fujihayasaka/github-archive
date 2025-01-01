# typed: true
# frozen_string_literal: true

module StatusCheckConfig::Defaults
  module Failure
    def state
      StatusCheckConfig::States::FAILURE
    end

    def icon
      "x"
    end

    def sentence_for_status
      "Some checks have failed"
    end

    def status_sentence_color_class
      "color-fg-danger"
    end

    def status_icon_color_class
      "color-fg-danger"
    end
  end
end
