# typed: true
# frozen_string_literal: true

module SecurityCenter
  class StateComponent < ApplicationComponent
    QUERY_PARSER = Search::Queries::SecurityCenter::SecretScanningQuery

    attr_reader :icon, :text, :is_highlighted

    def initialize(icon:, is_highlighted: false, text: nil)
      @icon = icon
      @is_highlighted = is_highlighted
      @text = text
    end

    def state_color
      is_highlighted ? :default : :muted
    end

    def state_font_weight
      is_highlighted ? :bold : :normal
    end
  end
end
