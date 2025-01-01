# typed: true
# frozen_string_literal: true

# Scope: Start from scratch with a table, board, and roadmap view.
# Custom Fields: None
# Views: Table, Board, Roadmap
# Insights: default
# Workflows: default

module MemexProject::DefaultTemplates
  BlankTemplate = {
      columns: [],
      views: [
        {
          name: "Table",
          layout: :table_layout
        },
        {
          name: "Board",
          layout: :board_layout,
        },
        {
          name: "Roadmap",
          layout: :roadmap_layout
        },
      ],
    }.freeze
end
