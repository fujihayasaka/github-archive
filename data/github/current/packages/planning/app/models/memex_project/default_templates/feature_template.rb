# typed: true
# frozen_string_literal: true

# Scope: Plan and track an individual feature across one week iterations.
# Custom Fields: Status, Iteration (one week), Linked pull requests, Estimate (number)
# Views: Home, Current Iteration, Next iteration, Planning
# Insights: Current iteration, Velocity
# Workflows: default

module MemexProject::DefaultTemplates
  FeatureTemplate = {
      columns: [
        {
          name: MemexProjectColumn::TITLE_COLUMN_NAME,
          data_type: :title,
          default_column: true,
          user_defined: true
        },
        {
          name: MemexProjectColumn::ASSIGNEES_COLUMN_NAME,
          data_type: :assignees,
          default_column: true
        },
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
          name: "Iteration",
          data_type: :iteration,
          default_column: false,
          user_defined: true,
          settings: {
            configuration: {
              start_day: 1,
              duration: 7,
              ahead_count: 4,
              iterations: [
                {
                  title: "Iteration",
                  start_date: Date.today.to_s,
                  duration: 7
                },
                {
                  title: "Iteration 2",
                  start_date: (Date.today + 7.days).to_s,
                  duration: 7
                }
              ]
            }
          }
        },
        {
          name: MemexProjectColumn::LINKED_PULL_REQUESTS_COLUMN_NAME,
          data_type: :linked_pull_requests,
          user_defined: true
        },
        {
          name: "Estimate",
          data_type: :number,
          user_defined: true
        }
      ],
      views: [
        {
          name: "Home",
          visible_fields_by_name: %w[title assignees status iteration estimate linked-pull-requests labels],
          layout: :table_layout
        },
        {
          name: "Current iteration",
          visible_fields_by_name: %w[title assignees status estimate linked-pull-requests],
          layout: :board_layout,
          filter: "iteration:@current"
        },
        {
          name: "Next iteration",
          visible_fields_by_name: %w[title assignees status estimate linked-pull-requests],
          layout: :board_layout,
          filter: "iteration:@next"
        },
        {
          name: "Planning",
          visible_fields_by_name: %w[title assignees iteration estimate status],
          layout: :table_layout,
          group_by_fields_by_name: ["iteration"]
        },
      ],
      insights: [
        {
          name: "Current iteration",
          configuration: {
            type: "line",
            xAxis: {
              dataSource: {
                columnName: "status"
              }
            },
            yAxis: {
              aggregate: {
                operation: "count"
              }
            },
            filter: "iteration:@current"
          }
        },
        {
          name: "Velocity",
          configuration: {
            type: "column",
            xAxis: {
              dataSource: {
                columnName: "iteration"
              }
            },
            yAxis: {
              aggregate: {
                operation: "sum",
                columnNames: ["estimate"]
              }
            },
            filter: ""
          }
        }
      ]
    }.freeze
end
