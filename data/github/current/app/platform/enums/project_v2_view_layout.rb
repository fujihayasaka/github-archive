# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectV2ViewLayout < Platform::Enums::Base
      description "The layout of a project v2 view."

      value "BOARD_LAYOUT", "Board layout", value: "board_layout"
      value "TABLE_LAYOUT", "Table layout", value: "table_layout"
      value "ROADMAP_LAYOUT", "Roadmap layout", value: "roadmap_layout"

    end
  end
end
