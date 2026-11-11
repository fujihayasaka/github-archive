# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectV2SingleSelectFieldOptionColor < Platform::Enums::Base
      description "The display color of a single-select field option."
      visibility :public, environments: [:dotcom, :enterprise]

      value "GRAY", "GRAY", value: "GRAY"
      value "BLUE", "BLUE", value: "BLUE"
      value "GREEN", "GREEN", value: "GREEN"
      value "YELLOW", "YELLOW", value: "YELLOW"
      value "ORANGE", "ORANGE", value: "ORANGE"
      value "RED", "RED", value: "RED"
      value "PINK", "PINK", value: "PINK"
      value "PURPLE", "PURPLE", value: "PURPLE"
    end
  end
end
