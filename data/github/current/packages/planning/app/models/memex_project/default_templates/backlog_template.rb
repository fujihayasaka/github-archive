# typed: true
# frozen_string_literal: true

# Scope: Define and plan your teams backlog using a kanban board.
# Custom Fields: Status, Linked pull requests, Priority,  Size
# Views: Backlog, By priority, By size
# Insights: Priority
# Workflows: default

module MemexProject::DefaultTemplates
  BacklogTemplate = {
      columns: [
        {
          name: MemexProjectColumn::STATUS_COLUMN_NAME,
          data_type: :single_select,
          default_column: true,
          user_defined: true,
          settings: {
            # We intentionally hard-code option IDs in this configuration to make
            # sure that the client can immediately identify a single-select option
            # after a memex has been created (without refreshing the page that was
            # initialized with the default columns of a memex).
            options: [
              {
                name: "🆕 New",
                color: "BLUE",
                description: ""
              },
              {
                name: "📋 Backlog",
                color: "GRAY",
                description: ""
              },
              {
                name: "🔖 Ready",
                color: "GREEN",
                description: ""
              },
              {
                name: "🏗 In progress",
                color: "YELLOW",
                description: ""
              },
              {
                name: "👀 In review",
                color: "ORANGE",
                description: ""
              },
              {
                name: "✅ Done",
                color: "PURPLE",
                description: ""
              }
            ]
          }
        },
        {
          name: MemexProjectColumn::LINKED_PULL_REQUESTS_COLUMN_NAME,
          data_type: :linked_pull_requests,
          user_defined: true
        },
        {
          name: "Priority",
          data_type: :single_select,
          default_column: true,
          user_defined: true,
          settings: {
            options: [
              {
                name: "🌋 Urgent",
                color: "RED",
                description: ""
              },
              {
                name: "🏔 High",
                color: "YELLOW",
                description: ""
              },
              {
                name: "🏕 Medium",
                color: "GREEN",
                description: ""
              },
              {
                name: "🏝 Low",
                color: "BLUE",
                description: ""
              }
            ]
          }
        },
        {
          name: "Size",
          data_type: :single_select,
          default_column: true,
          user_defined: true,
          settings: {
            options: [
              {
                name: "🐋 X-Large",
                color: "RED",
                description: ""
              },
              {
                name: "🦑 Large",
                color: "ORANGE",
                description: ""
              },
              {
                name: "🐂 Medium",
                color: "YELLOW",
                description: ""
              },
              {
                name: "🐇 Small",
                color: "GREEN",
                description: ""
              },
              {
                name: "🦔 Tiny",
                color: "BLUE",
                description: ""
              }
            ]
          }
        }
      ],
      views: [
        {
          name: "Backlog",
          visible_fields_by_name: %w[title assignees status priority size linked-pull-requests labels],
          layout: :board_layout
        },
        {
          name: "By priority",
          visible_fields_by_name: %w[title assignees status priority size linked-pull-requests labels],
          layout: :table_layout,
          group_by_fields_by_name: ["priority"]
        },
        {
          name: "By size",
          visible_fields_by_name: %w[title assignees status priority size linked-pull-requests labels],
          layout: :table_layout,
          group_by_fields_by_name: ["size"]
        }
      ],
      insights: [
        {
          name: "Priority",
          configuration: {
            type: "line",
            xAxis: {
              dataSource: {
                columnName: "priority"
              },
              groupBy: {
                columnName: "size"
              }
            },
            yAxis: {
              aggregate: {
                operation: "count"
              }
            },
            filter: ""
          }
        }
      ]
    }.freeze
end
