# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectViewLayout < Platform::Enums::Base
      description "The layout of a project view."

      value "BOARD_LAYOUT", "Board layout", value: "board_layout"
      value "TABLE_LAYOUT", "Table layout", value: "table_layout"
    end
  end
end
